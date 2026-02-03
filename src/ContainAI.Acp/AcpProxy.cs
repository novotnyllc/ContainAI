// Main ACP Proxy implementation
using System.Collections.Concurrent;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using ContainAI.Acp.PathTranslation;
using ContainAI.Acp.Protocol;
using ContainAI.Acp.Sessions;

namespace ContainAI.Acp;

/// <summary>
/// ACP terminating proxy that handles ACP protocol from editors,
/// routes to containerized agents via cai exec.
/// </summary>
public sealed class AcpProxy : IDisposable
{
    private readonly ConcurrentDictionary<string, AcpSession> _sessions = new();
    private readonly OutputWriter _output;
    private readonly CancellationTokenSource _cts = new();
    private readonly string _agent;
    private readonly bool _testMode;
    private readonly bool _directSpawn;
    private readonly TextWriter _stderr;

    // Cached initialize params from editor (for forwarding to agents)
    private JsonNode? _cachedInitializeParams;

    /// <summary>
    /// Creates a new ACP proxy.
    /// </summary>
    /// <param name="agent">The agent binary name (any agent supporting --acp flag).</param>
    /// <param name="stdout">Stream for JSON-RPC output.</param>
    /// <param name="stderr">Stream for diagnostic output.</param>
    /// <param name="testMode">If true, skips container-side preflight checks.</param>
    /// <param name="directSpawn">If true, spawns agent directly without cai exec.</param>
    public AcpProxy(
        string agent,
        Stream stdout,
        TextWriter stderr,
        bool testMode = false,
        bool directSpawn = false)
    {
        _agent = agent;
        _output = new OutputWriter(stdout);
        _stderr = stderr;
        _testMode = testMode;
        _directSpawn = directSpawn;

        // No validation - any agent name is accepted.
        // Validation happens at runtime when the agent binary is executed.
        // - For direct spawn: Process.Start() will fail if binary doesn't exist
        // - For containerized: cai exec wraps with preflight check for clear error
    }

    /// <summary>
    /// Runs the proxy, reading from stdin until EOF or cancellation.
    /// </summary>
    public async Task<int> RunAsync(Stream stdin, CancellationToken cancellationToken = default)
    {
        using var linkedCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, _cts.Token);
        var ct = linkedCts.Token;

        // Start output writer task
        var writerTask = _output.RunAsync(ct);

        try
        {
            // Read messages from stdin (NDJSON)
            using var reader = new StreamReader(stdin, Encoding.UTF8);
            while (!ct.IsCancellationRequested)
            {
                string? line;
                try
                {
                    line = await reader.ReadLineAsync(ct);
                }
                catch (OperationCanceledException)
                {
                    break;
                }

                if (line == null)
                    break; // EOF

                if (string.IsNullOrWhiteSpace(line))
                    continue;

                try
                {
                    await ProcessMessageAsync(line);
                }
                catch (JsonException ex)
                {
                    await _stderr.WriteLineAsync($"JSON parse error: {ex.Message}");
                }
                catch (Exception ex)
                {
                    await _stderr.WriteLineAsync($"Error processing message: {ex.Message}");
                }
            }

            // stdin EOF or cancellation - graceful shutdown
            await ShutdownAsync();
        }
        catch (Exception ex)
        {
            await _stderr.WriteLineAsync($"Fatal error: {ex.Message}");
            return 1;
        }
        finally
        {
            await _cts.CancelAsync();
            _output.Complete();
            try { await writerTask; } catch { }
        }

        return 0;
    }

    /// <summary>
    /// Signals the proxy to stop.
    /// </summary>
    public void Cancel()
    {
        _cts.Cancel();
    }

    private async Task ProcessMessageAsync(string line)
    {
        var message = JsonSerializer.Deserialize(line, AcpJsonContext.Default.JsonRpcMessage);
        if (message == null)
            return;

        // Route based on method
        switch (message.Method)
        {
            case "initialize":
                await HandleInitializeAsync(message);
                break;

            case "session/new":
                await HandleSessionNewAsync(message);
                break;

            case "session/prompt":
            case "session/end":
                await RouteToSessionAsync(message);
                break;

            default:
                // For unknown methods: only respond with error if it's a request (has id)
                // JSON-RPC forbids responding to notifications (no id)
                if (message.Id != null)
                {
                    await _output.EnqueueAsync(JsonRpcHelpers.CreateErrorResponse(
                        message.Id,
                        JsonRpcErrorCodes.MethodNotFound,
                        $"Method not found: {message.Method}"));
                }
                // Notifications are silently ignored (per JSON-RPC spec)
                break;
        }
    }

    private async Task HandleInitializeAsync(JsonRpcMessage message)
    {
        // Cache editor's initialize params for forwarding to agents
        _cachedInitializeParams = message.Params?.DeepClone();

        // Extract requested protocol version (or use default)
        var requestedVersion = "2025-01-01";
        if (message.Params is JsonObject paramsObj &&
            paramsObj.TryGetPropertyValue("protocolVersion", out var versionNode))
        {
            requestedVersion = versionNode?.GetValue<string>() ?? "2025-01-01";
        }

        // Respond with proxy capabilities using negotiated version
        var response = new JsonRpcMessage
        {
            Id = message.Id,
            Result = new JsonObject
            {
                ["protocolVersion"] = requestedVersion,
                ["capabilities"] = new JsonObject
                {
                    ["multiSession"] = true
                },
                ["serverInfo"] = new JsonObject
                {
                    ["name"] = "containai-acp-proxy",
                    ["version"] = "0.1.0"
                }
            }
        };

        await _output.EnqueueAsync(response);
    }

    private async Task HandleSessionNewAsync(JsonRpcMessage message)
    {
        // Parse session/new parameters
        string? cwd = null;
        JsonNode? mcpServersNode = null;

        if (message.Params is JsonObject paramsObj)
        {
            if (paramsObj.TryGetPropertyValue("cwd", out var cwdNode))
                cwd = cwdNode?.GetValue<string>();
            if (paramsObj.TryGetPropertyValue("mcpServers", out mcpServersNode))
            {
                // mcpServersNode captured
            }
        }

        var originalCwd = cwd ?? Directory.GetCurrentDirectory();

        // Resolve workspace root
        var workspace = await WorkspaceResolver.ResolveAsync(originalCwd, _cts.Token);

        // Create session
        var session = new AcpSession(workspace);

        try
        {
            // Create path translator for this workspace
            var pathTranslator = new PathTranslator(workspace);

            // Spawn agent process
            var spawner = new AgentSpawner(_directSpawn, _stderr);
            var process = spawner.SpawnAgent(session, _agent);
            session.AgentProcess = process;

            // Start reader task to handle out-of-order responses and notifications
            session.ReaderTask = Task.Run(() => ReadAgentOutputLoopAsync(session));

            // Build initialize request for agent (forward editor's params)
            var initParams = new JsonObject();
            if (_cachedInitializeParams is JsonObject cachedParams)
            {
                // Forward protocolVersion from editor (or default)
                if (cachedParams.TryGetPropertyValue("protocolVersion", out var pv))
                {
                    initParams["protocolVersion"] = pv?.DeepClone();
                }
                else
                {
                    initParams["protocolVersion"] = "2025-01-01";
                }
                // Forward clientInfo if present
                if (cachedParams.TryGetPropertyValue("clientInfo", out var clientInfo))
                {
                    initParams["clientInfo"] = clientInfo?.DeepClone();
                }
                // Forward capabilities if present
                if (cachedParams.TryGetPropertyValue("capabilities", out var caps))
                {
                    initParams["capabilities"] = caps?.DeepClone();
                }
            }
            else
            {
                initParams["protocolVersion"] = "2025-01-01";
            }

            var initRequestId = "init-" + session.ProxySessionId;
            var initRequest = new JsonRpcMessage
            {
                Id = initRequestId,
                Method = "initialize",
                Params = initParams
            };

            // Wait for initialize response (with timeout)
            // IMPORTANT: Register pending request BEFORE writing to avoid race condition
            var initResponse = await session.SendAndWaitForResponseAsync(initRequest, initRequestId, TimeSpan.FromSeconds(30));
            if (initResponse == null)
            {
                throw new Exception("Agent did not respond to initialize");
            }

            // Check for agent error in initialize response
            if (initResponse.Error != null)
            {
                var errMsg = initResponse.Error.Message ?? "Unknown error";
                throw new Exception($"Agent initialize failed: {errMsg}");
            }

            // Calculate container cwd - preserve relative path from workspace root
            var containerCwd = pathTranslator.TranslateToContainer(originalCwd);

            // Create session/new request for agent
            var sessionNewParams = new JsonObject
            {
                ["cwd"] = containerCwd
            };

            // Translate MCP server args if provided
            if (mcpServersNode != null)
            {
                var translatedMcp = pathTranslator.TranslateMcpServers(mcpServersNode);
                sessionNewParams["mcpServers"] = translatedMcp;
            }

            var sessionNewRequestId = "session-new-" + session.ProxySessionId;
            var sessionNewRequest = new JsonRpcMessage
            {
                Id = sessionNewRequestId,
                Method = "session/new",
                Params = sessionNewParams
            };

            // Wait for session/new response
            // IMPORTANT: Register pending request BEFORE writing to avoid race condition
            var sessionNewResponse = await session.SendAndWaitForResponseAsync(sessionNewRequest, sessionNewRequestId, TimeSpan.FromSeconds(30));
            if (sessionNewResponse == null)
            {
                throw new Exception("Agent did not respond to session/new");
            }

            // Check for agent error in session/new response
            if (sessionNewResponse.Error != null)
            {
                var errMsg = sessionNewResponse.Error.Message ?? "Unknown error";
                throw new Exception($"Agent session/new failed: {errMsg}");
            }

            // Extract agent's session ID - required for routing
            if (sessionNewResponse.Result is JsonObject resultObj &&
                resultObj.TryGetPropertyValue("sessionId", out var sessionIdNode))
            {
                session.AgentSessionId = sessionIdNode?.GetValue<string>() ?? "";
            }

            // Validate we got a session ID
            if (string.IsNullOrEmpty(session.AgentSessionId))
            {
                throw new Exception("Agent did not return a session ID");
            }

            // Register session
            _sessions[session.ProxySessionId] = session;

            // Respond to editor with proxy session ID
            var response = new JsonRpcMessage
            {
                Id = message.Id,
                Result = new JsonObject
                {
                    ["sessionId"] = session.ProxySessionId
                }
            };
            await _output.EnqueueAsync(response);
        }
        catch (Exception ex)
        {
            // Clean up on failure
            session.Dispose();

            // Only respond if this was a request (has id)
            if (message.Id != null)
            {
                await _output.EnqueueAsync(JsonRpcHelpers.CreateErrorResponse(
                    message.Id,
                    JsonRpcErrorCodes.SessionCreationFailed,
                    $"Failed to create session: {ex.Message}"));
            }
        }
    }

    private async Task RouteToSessionAsync(JsonRpcMessage message)
    {
        // Extract sessionId from params
        string? sessionId = null;
        if (message.Params is JsonObject paramsObj &&
            paramsObj.TryGetPropertyValue("sessionId", out var sessionIdNode))
        {
            sessionId = sessionIdNode?.GetValue<string>();
        }

        if (string.IsNullOrEmpty(sessionId) || !_sessions.TryGetValue(sessionId, out var session))
        {
            // Only respond with error if this is a request (has id)
            if (message.Id != null)
            {
                await _output.EnqueueAsync(JsonRpcHelpers.CreateErrorResponse(
                    message.Id,
                    JsonRpcErrorCodes.SessionNotFound,
                    $"Session not found: {sessionId}"));
            }
            return;
        }

        // Handle session/end specially
        if (message.Method == "session/end")
        {
            await HandleSessionEndAsync(sessionId, message);
            return;
        }

        // Replace sessionId with agent's sessionId
        if (message.Params is JsonObject paramsToModify)
        {
            paramsToModify["sessionId"] = session.AgentSessionId;
        }

        // Forward to agent
        await session.WriteToAgentAsync(message);
    }

    private async Task HandleSessionEndAsync(string sessionId, JsonRpcMessage message)
    {
        if (!_sessions.TryRemove(sessionId, out var session))
            return;

        try
        {
            // Forward session/end to agent as a NOTIFICATION (no id) to avoid duplicate responses
            // The proxy handles the response to the editor, not the agent
            var endNotification = new JsonRpcMessage
            {
                // No Id - this is a notification, not a request
                Method = "session/end",
                Params = new JsonObject
                {
                    ["sessionId"] = session.AgentSessionId
                }
            };
            await session.WriteToAgentAsync(endNotification);

            // Wait for reader to complete (agent may send final messages)
            using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(5));
            try
            {
                if (session.ReaderTask != null)
                    await session.ReaderTask.WaitAsync(cts.Token);
            }
            catch (OperationCanceledException)
            {
                // Timeout - proceed with cleanup
            }
        }
        finally
        {
            session.Dispose();
        }

        // Acknowledge to editor (only if this was a request)
        if (message.Id != null)
        {
            await _output.EnqueueAsync(new JsonRpcMessage
            {
                Id = message.Id,
                Result = new JsonObject { }
            });
        }
    }

    private async Task ReadAgentOutputLoopAsync(AcpSession session)
    {
        try
        {
            var reader = session.AgentProcess?.StandardOutput;
            if (reader == null)
                return;

            string? line;
            while ((line = await reader.ReadLineAsync()) != null)
            {
                await ReadAgentOutputAsync(session, line);
            }
        }
        catch (Exception ex)
        {
            await _stderr.WriteLineAsync($"Agent reader error for session {session.ProxySessionId}: {ex.Message}");
        }
    }

    private async Task ReadAgentOutputAsync(AcpSession session, string line)
    {
        if (string.IsNullOrWhiteSpace(line))
            return;

        try
        {
            var message = JsonSerializer.Deserialize(line, AcpJsonContext.Default.JsonRpcMessage);
            if (message == null)
                return;

            // Check if this is a response to a pending request
            // Note: NormalizeId extracts raw value from JsonNode (avoids quoted strings)
            if (message.Id != null && (message.Result != null || message.Error != null))
            {
                var idStr = JsonRpcHelpers.NormalizeId(message.Id);
                if (idStr != null && session.TryCompleteResponse(idStr, message))
                {
                    // Response was consumed by a waiter
                    return;
                }
            }

            // Replace agent's sessionId with proxy's sessionId in responses/notifications
            if (message.Params is JsonObject paramsObj)
            {
                if (paramsObj.TryGetPropertyValue("sessionId", out var sidNode) &&
                    sidNode?.GetValue<string>() == session.AgentSessionId)
                {
                    paramsObj["sessionId"] = session.ProxySessionId;
                }
            }

            // Forward to editor
            await _output.EnqueueAsync(message);
        }
        catch (JsonException)
        {
            // Skip malformed messages
        }
    }

    private async Task ShutdownAsync()
    {
        // End all sessions gracefully
        foreach (var sessionId in _sessions.Keys.ToList())
        {
            if (_sessions.TryRemove(sessionId, out var session))
            {
                try
                {
                    // Send session/end to agent
                    var endRequest = new JsonRpcMessage
                    {
                        Method = "session/end",
                        Params = new JsonObject
                        {
                            ["sessionId"] = session.AgentSessionId
                        }
                    };
                    await session.WriteToAgentAsync(endRequest);

                    // Wait briefly for graceful shutdown
                    using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(2));
                    try
                    {
                        if (session.ReaderTask != null)
                            await session.ReaderTask.WaitAsync(cts.Token);
                    }
                    catch (OperationCanceledException)
                    {
                        // Timeout
                    }
                }
                finally
                {
                    session.Dispose();
                }
            }
        }
    }

    public void Dispose()
    {
        _cts.Dispose();
    }
}
