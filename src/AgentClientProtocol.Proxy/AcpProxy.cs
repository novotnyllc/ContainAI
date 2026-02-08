// Main ACP Proxy implementation
using System.Collections.Concurrent;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization.Metadata;
using AgentClientProtocol.Proxy.PathTranslation;
using AgentClientProtocol.Proxy.Protocol;
using AgentClientProtocol.Proxy.Sessions;

namespace AgentClientProtocol.Proxy;

/// <summary>
/// ACP terminating proxy that handles ACP protocol from editors,
/// routes to containerized agents via cai exec.
/// </summary>
public sealed class AcpProxy : IDisposable
{
    private readonly ConcurrentDictionary<string, AcpSession> sessions = new();
    private readonly OutputWriter output;
    private readonly CancellationTokenSource cts = new();
    private readonly string agent;
    private readonly IAgentSpawner agentSpawner;
    private readonly ErrorSink errorSink;

    // Cached initialize params from editor (for forwarding to agents)
    private InitializeRequestParams? cachedInitializeParams;

    /// <summary>
    /// Creates a new ACP proxy.
    /// </summary>
    /// <param name="agent">The agent binary name (any agent supporting --acp flag).</param>
    /// <param name="stdout">Stream for JSON-RPC output.</param>
    /// <param name="stderr">Stream for diagnostic output.</param>
    /// <param name="directSpawn">If true, spawns agent directly without cai exec.</param>
    /// <param name="agentSpawner">Optional custom agent spawner. If null, default spawner is used.</param>
    public AcpProxy(
        string agentName,
        Stream outputStream,
        TextWriter errorWriter,
        bool directSpawn = false,
        IAgentSpawner? customAgentSpawner = null)
    {
        ArgumentNullException.ThrowIfNull(agentName);
        ArgumentNullException.ThrowIfNull(outputStream);
        ArgumentNullException.ThrowIfNull(errorWriter);

        agent = agentName;
        output = new OutputWriter(outputStream);
        errorSink = new ErrorSink(errorWriter);
        agentSpawner = customAgentSpawner ?? new AgentSpawner(directSpawn, errorWriter);

        // No static allow-list here; agent validation happens when spawn starts.
    }

    /// <summary>
    /// Runs the proxy, reading from stdin until EOF or cancellation.
    /// </summary>
    public async Task<int> RunAsync(Stream stdin, CancellationToken cancellationToken = default)
    {
        using var linkedCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, cts.Token);
        var ct = linkedCts.Token;

        // Start output writer task
        var writerTask = output.RunAsync(ct);

        try
        {
            // Read messages from stdin (NDJSON)
            using var reader = new StreamReader(stdin, Encoding.UTF8);
            while (!ct.IsCancellationRequested)
            {
                string? line;
                try
                {
                    line = await reader.ReadLineAsync(ct).ConfigureAwait(false);
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
                    await ProcessMessageAsync(line).ConfigureAwait(false);
                }
                catch (JsonException ex)
                {
                    await errorSink.WriteLineAsync($"JSON parse error: {ex.Message}").ConfigureAwait(false);
                }
                catch (InvalidOperationException ex)
                {
                    await errorSink.WriteLineAsync($"Error processing message: {ex.Message}").ConfigureAwait(false);
                }
                catch (IOException ex)
                {
                    await errorSink.WriteLineAsync($"Error processing message: {ex.Message}").ConfigureAwait(false);
                }
            }

            // stdin EOF or cancellation - graceful shutdown
            await ShutdownAsync().ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is InvalidOperationException or IOException or UnauthorizedAccessException)
        {
            await errorSink.WriteLineAsync($"Fatal error: {ex.Message}").ConfigureAwait(false);
            return 1;
        }
        finally
        {
            output.Complete();
            try
            {
                await writerTask.ConfigureAwait(false);
            }
            catch (OperationCanceledException ex)
            {
                await errorSink.WriteLineAsync($"Output flush canceled: {ex.Message}").ConfigureAwait(false);
            }

            await cts.CancelAsync().ConfigureAwait(false);
        }

        return 0;
    }

    /// <summary>
    /// Signals the proxy to stop.
    /// </summary>
    public void Cancel() => cts.Cancel();

    private async Task ProcessMessageAsync(string line)
    {
        var message = JsonSerializer.Deserialize(line, AcpJsonContext.Default.JsonRpcEnvelope);
        if (message == null)
            return;

        // Ignore editor-originated responses (no method + id/result-or-error).
        // Proxy only handles requests/notifications from editor and forwards to agents.
        if (message.Method == null && message.Id != null && (message.Result != null || message.Error != null))
            return;

        // Route based on method
        switch (message.Method)
        {
            case "initialize":
                await HandleInitializeAsync(message).ConfigureAwait(false);
                break;

            case "session/new":
                await HandleSessionNewAsync(message).ConfigureAwait(false);
                break;

            case "session/prompt":
            case "session/end":
                await RouteToSessionAsync(message).ConfigureAwait(false);
                break;

            default:
                // For unknown methods: only respond with error if it's a request (has id)
                // JSON-RPC forbids responding to notifications (no id)
                if (message.Id != null)
                {
                    await output.EnqueueAsync(JsonRpcHelpers.CreateErrorResponse(
                        message.Id,
                        JsonRpcErrorCodes.MethodNotFound,
                        $"Method not found: {message.Method}")).ConfigureAwait(false);
                }
                // Notifications are silently ignored (per JSON-RPC spec)
                break;
        }
    }

    private async Task HandleInitializeAsync(JsonRpcEnvelope message)
    {
        var initializeParams = DeserializeElement(message.Params, AcpJsonContext.Default.InitializeRequestParams) ?? new InitializeRequestParams();
        cachedInitializeParams = initializeParams;
        var requestedVersion = initializeParams.ProtocolVersion ?? "2025-01-01";

        // Respond with proxy capabilities using negotiated version
        var response = new JsonRpcEnvelope
        {
            Id = message.Id,
            Result = SerializeElement(
                new InitializeResultPayload
                {
                    ProtocolVersion = requestedVersion,
                    Capabilities = new ProxyCapabilities { MultiSession = true },
                    ServerInfo = new ProxyServerInfo
                    {
                        Name = "containai-acp-proxy",
                        Version = "0.1.0",
                    },
                },
                AcpJsonContext.Default.InitializeResultPayload)
        };

        if (message.Id != null)
        {
            await output.EnqueueAsync(response).ConfigureAwait(false);
        }
    }

    private async Task HandleSessionNewAsync(JsonRpcEnvelope message)
    {
        var sessionNewInput = DeserializeElement(message.Params, AcpJsonContext.Default.SessionNewRequestParams) ?? new SessionNewRequestParams();
        var cwd = sessionNewInput.Cwd;
        var mcpServersNode = sessionNewInput.McpServers;
        var originalCwd = cwd ?? Directory.GetCurrentDirectory();

        // Resolve workspace root
        var workspace = await WorkspaceResolver.ResolveAsync(originalCwd, cts.Token).ConfigureAwait(false);

        // Create session
        var session = new AcpSession(workspace);

        try
        {
            // Create path translator for this workspace
            var pathTranslator = new PathTranslator(workspace);

            // Spawn agent process
            await agentSpawner.SpawnAgentAsync(session, agent, cts.Token).ConfigureAwait(false);

            // Start reader task to handle out-of-order responses and notifications
            session.ReaderTask = Task.Run(() => ReadAgentOutputLoopAsync(session));

            // Build initialize request for agent (forward editor's params)
            var initParams = new InitializeRequestParams
            {
                ProtocolVersion = cachedInitializeParams?.ProtocolVersion ?? "2025-01-01",
                ClientInfo = cachedInitializeParams?.ClientInfo is { } clientInfo ? clientInfo.Clone() : null,
                Capabilities = cachedInitializeParams?.Capabilities is { } capabilities ? capabilities.Clone() : null,
            };
            MergeExtensionData(initParams.ExtensionData, cachedInitializeParams?.ExtensionData);

            var initRequestId = "init-" + session.ProxySessionId;
            var initRequest = new JsonRpcEnvelope
            {
                Id = JsonRpcId.FromString(initRequestId),
                Method = "initialize",
                Params = SerializeElement(initParams, AcpJsonContext.Default.InitializeRequestParams),
            };

            // Wait for initialize response (with timeout)
            // IMPORTANT: Register pending request BEFORE writing to avoid race condition
            var initResponse = await session.SendAndWaitForResponseAsync(initRequest, initRequestId, TimeSpan.FromSeconds(30)).ConfigureAwait(false);
            if (initResponse == null)
            {
                throw new TimeoutException("Agent did not respond to initialize");
            }

            // Check for agent error in initialize response
            if (initResponse.Error != null)
            {
                var errMsg = initResponse.Error.Message ?? "Unknown error";
                throw new InvalidOperationException($"Agent initialize failed: {errMsg}");
            }

            // Calculate container cwd - preserve relative path from workspace root
            var containerCwd = pathTranslator.TranslateToContainer(originalCwd);

            // Create session/new request for agent
            var sessionNewParams = new SessionNewRequestParams
            {
                Cwd = containerCwd,
            };
            MergeExtensionData(sessionNewParams.ExtensionData, sessionNewInput.ExtensionData);

            // Translate MCP server args if provided
            if (mcpServersNode is { } mcpServersValue)
            {
                var translatedMcp = pathTranslator.TranslateMcpServers(mcpServersValue);
                sessionNewParams.McpServers = translatedMcp;
            }

            var sessionNewRequestId = "session-new-" + session.ProxySessionId;
            var sessionNewRequest = new JsonRpcEnvelope
            {
                Id = JsonRpcId.FromString(sessionNewRequestId),
                Method = "session/new",
                Params = SerializeElement(sessionNewParams, AcpJsonContext.Default.SessionNewRequestParams),
            };

            // Wait for session/new response
            // IMPORTANT: Register pending request BEFORE writing to avoid race condition
            var sessionNewResponse = await session.SendAndWaitForResponseAsync(sessionNewRequest, sessionNewRequestId, TimeSpan.FromSeconds(30)).ConfigureAwait(false);
            if (sessionNewResponse == null)
            {
                throw new TimeoutException("Agent did not respond to session/new");
            }

            // Check for agent error in session/new response
            if (sessionNewResponse.Error != null)
            {
                var errMsg = sessionNewResponse.Error.Message ?? "Unknown error";
                throw new InvalidOperationException($"Agent session/new failed: {errMsg}");
            }

            var sessionNewResult = DeserializeElement(sessionNewResponse.Result, AcpJsonContext.Default.SessionNewResponsePayload);
            session.AgentSessionId = sessionNewResult?.SessionId ?? string.Empty;

            // Validate we got a session ID
            if (string.IsNullOrEmpty(session.AgentSessionId))
            {
                throw new InvalidOperationException("Agent did not return a session ID");
            }

            // Register session
            sessions[session.ProxySessionId] = session;

            // Respond to editor with proxy session ID
            var response = new JsonRpcEnvelope
            {
                Id = message.Id,
                Result = SerializeElement(
                    new SessionNewResponsePayload { SessionId = session.ProxySessionId },
                    AcpJsonContext.Default.SessionNewResponsePayload),
            };
            if (message.Id != null)
            {
                await output.EnqueueAsync(response).ConfigureAwait(false);
            }
        }
        catch (Exception ex) when (ex is InvalidOperationException or TimeoutException or JsonException or IOException)
        {
            session.Dispose();

            if (message.Id != null)
            {
                await output.EnqueueAsync(JsonRpcHelpers.CreateErrorResponse(
                    message.Id,
                    JsonRpcErrorCodes.SessionCreationFailed,
                    $"Failed to create session: {ex.Message}")).ConfigureAwait(false);
            }
        }
    }

    private async Task RouteToSessionAsync(JsonRpcEnvelope message)
    {
        // Extract sessionId from params
        var scopedParams = DeserializeElement(message.Params, AcpJsonContext.Default.SessionScopedParams);
        var sessionId = scopedParams?.SessionId;

        if (string.IsNullOrEmpty(sessionId) || !sessions.TryGetValue(sessionId, out var session))
        {
            // Only respond with error if this is a request (has id)
            if (message.Id != null)
            {
                await output.EnqueueAsync(JsonRpcHelpers.CreateErrorResponse(
                    message.Id,
                    JsonRpcErrorCodes.SessionNotFound,
                    $"Session not found: {sessionId}")).ConfigureAwait(false);
            }
            return;
        }

        // Handle session/end specially
        if (message.Method == "session/end")
        {
            await HandleSessionEndAsync(sessionId, message).ConfigureAwait(false);
            return;
        }

        // Replace sessionId with agent's sessionId
        if (scopedParams != null)
        {
            scopedParams.SessionId = session.AgentSessionId;
            message.Params = SerializeElement(scopedParams, AcpJsonContext.Default.SessionScopedParams);
        }

        // Forward to agent
        await session.WriteToAgentAsync(message).ConfigureAwait(false);
    }

    private async Task HandleSessionEndAsync(string sessionId, JsonRpcEnvelope message)
    {
        if (!sessions.TryRemove(sessionId, out var session))
            return;

        try
        {
            // Forward session/end to agent as a NOTIFICATION (no id) to avoid duplicate responses
            // The proxy handles the response to the editor, not the agent
            var endNotification = new JsonRpcEnvelope
            {
                // No Id - this is a notification, not a request
                Method = "session/end",
                Params = SerializeElement(
                    new SessionScopedParams { SessionId = session.AgentSessionId },
                    AcpJsonContext.Default.SessionScopedParams),
            };
            await session.WriteToAgentAsync(endNotification).ConfigureAwait(false);

            // Wait for reader to complete (agent may send final messages)
            using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(5));
            try
            {
                if (session.ReaderTask != null)
                    await session.ReaderTask.WaitAsync(cts.Token).ConfigureAwait(false);
            }
            catch (OperationCanceledException ex)
            {
                await errorSink.WriteLineAsync($"Session end timeout for {session.ProxySessionId}: {ex.Message}").ConfigureAwait(false);
            }
        }
        finally
        {
            session.Dispose();
        }

        // Acknowledge to editor (only if this was a request)
        if (message.Id != null)
        {
            await output.EnqueueAsync(new JsonRpcEnvelope
            {
                Id = message.Id,
                Result = SerializeElement(
                    new SessionNewResponsePayload(),
                    AcpJsonContext.Default.SessionNewResponsePayload),
            }).ConfigureAwait(false);
        }
    }

    private async Task ReadAgentOutputLoopAsync(AcpSession session)
    {
        try
        {
            var output = session.AgentOutput;
            if (output == null)
                return;

            await foreach (var line in output.ReadAllAsync(session.CancellationToken).ConfigureAwait(false))
            {
                await ReadAgentOutputAsync(session, line).ConfigureAwait(false);
            }
        }
        catch (Exception ex) when (ex is IOException or ObjectDisposedException or InvalidOperationException)
        {
            await errorSink.WriteLineAsync($"Agent reader error for session {session.ProxySessionId}: {ex.Message}").ConfigureAwait(false);
        }
    }

    private async Task ReadAgentOutputAsync(AcpSession session, string line)
    {
        if (string.IsNullOrWhiteSpace(line))
            return;

        try
        {
            var message = JsonSerializer.Deserialize(line, AcpJsonContext.Default.JsonRpcEnvelope);
            if (message == null)
                return;

            // Check if this is a response to a pending request
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
            var scopedParams = DeserializeElement(message.Params, AcpJsonContext.Default.SessionScopedParams);
            if (scopedParams is not null && scopedParams.SessionId == session.AgentSessionId)
            {
                scopedParams.SessionId = session.ProxySessionId;
                message.Params = SerializeElement(scopedParams, AcpJsonContext.Default.SessionScopedParams);
            }

            // Forward to editor
            await output.EnqueueAsync(message).ConfigureAwait(false);
        }
        catch (JsonException ex)
        {
            await errorSink.WriteLineAsync($"Malformed agent output skipped for session {session.ProxySessionId}: {ex.Message}").ConfigureAwait(false);
        }
    }

    private async Task ShutdownAsync()
    {
        // End all sessions gracefully
        foreach (var sessionId in sessions.Keys.ToList())
        {
            if (sessions.TryRemove(sessionId, out var session))
            {
                try
                {
                    // Send session/end to agent
                    var endRequest = new JsonRpcEnvelope
                    {
                        Method = "session/end",
                        Params = SerializeElement(
                            new SessionScopedParams { SessionId = session.AgentSessionId },
                            AcpJsonContext.Default.SessionScopedParams),
                    };
                    await session.WriteToAgentAsync(endRequest).ConfigureAwait(false);

                    // Wait briefly for graceful shutdown
                    using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(2));
                    try
                    {
                        if (session.ReaderTask != null)
                            await session.ReaderTask.WaitAsync(cts.Token).ConfigureAwait(false);
                    }
                    catch (OperationCanceledException ex)
                    {
                        await errorSink.WriteLineAsync($"Session shutdown timeout for {session.ProxySessionId}: {ex.Message}").ConfigureAwait(false);
                    }
                }
                finally
                {
                    session.Dispose();
                }
            }
        }
    }

    public void Dispose() => cts.Dispose();

    private sealed class ErrorSink(TextWriter writer)
    {
        public ValueTask WriteLineAsync(string message)
            => new(writer.WriteLineAsync(message));
    }

    private static T? DeserializeElement<T>(JsonRpcData? payload, JsonTypeInfo<T> typeInfo)
    {
        if (payload is null || payload.Value.Element.ValueKind == JsonValueKind.Null)
        {
            return default;
        }

        return JsonSerializer.Deserialize(payload.Value.Element.GetRawText(), typeInfo);
    }

    private static JsonRpcData SerializeElement<T>(T value, JsonTypeInfo<T> typeInfo)
        => JsonSerializer.SerializeToElement(value, typeInfo);

    private static void MergeExtensionData(Dictionary<string, JsonElement> destination, Dictionary<string, JsonElement>? source)
    {
        if (source is null || source.Count == 0)
        {
            return;
        }

        foreach (var (key, value) in source)
        {
            destination[key] = value.Clone();
        }
    }
}
