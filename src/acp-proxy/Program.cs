// ContainAI ACP Terminating Proxy
// Handles ACP protocol from editors, routes to containerized agents via cai exec

using System.Collections.Concurrent;
using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;
using System.Threading.Channels;

namespace ContainAI.AcpProxy;

public static class Program
{
    private static readonly ConcurrentDictionary<string, Session> Sessions = new();
    private static readonly OutputWriter Output = new(Console.OpenStandardOutput());
    private static readonly CancellationTokenSource Cts = new();

    // Cached initialize params from editor (for forwarding to agents)
    private static JsonNode? CachedInitializeParams;

    public static async Task<int> Main(string[] args)
    {
        var agent = args.Length > 0 ? args[0] : "claude";

        // Validate agent (unless test mode)
        var testMode = Environment.GetEnvironmentVariable("CAI_ACP_TEST_MODE") == "1";
        if (!testMode)
        {
            if (agent != "claude" && agent != "gemini")
            {
                await Console.Error.WriteLineAsync($"Unsupported agent: {agent}");
                return 1;
            }
        }

        // Start output writer task
        var writerTask = Output.RunAsync(Cts.Token);

        // Set up console cancel handler for graceful shutdown
        Console.CancelKeyPress += (_, e) =>
        {
            e.Cancel = true;
            // Signal cancellation - the main loop will handle shutdown
            Cts.Cancel();
        };

        try
        {
            // Read messages from stdin (NDJSON)
            using var reader = new StreamReader(Console.OpenStandardInput(), Encoding.UTF8);
            while (!Cts.IsCancellationRequested)
            {
                string? line;
                try
                {
                    line = await reader.ReadLineAsync(Cts.Token);
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
                    await ProcessMessageAsync(line, agent);
                }
                catch (JsonException ex)
                {
                    await Console.Error.WriteLineAsync($"JSON parse error: {ex.Message}");
                }
                catch (Exception ex)
                {
                    await Console.Error.WriteLineAsync($"Error processing message: {ex.Message}");
                }
            }

            // stdin EOF or cancellation - graceful shutdown
            await ShutdownAsync();
        }
        catch (Exception ex)
        {
            await Console.Error.WriteLineAsync($"Fatal error: {ex.Message}");
            return 1;
        }
        finally
        {
            await Cts.CancelAsync();
            Output.Complete();
            try { await writerTask; } catch { }
        }

        return 0;
    }

    private static async Task ProcessMessageAsync(string line, string agent)
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
                await HandleSessionNewAsync(message, agent);
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
                    await Output.EnqueueAsync(new JsonRpcMessage
                    {
                        Id = message.Id,
                        Error = new JsonRpcError
                        {
                            Code = -32601,
                            Message = $"Method not found: {message.Method}"
                        }
                    });
                }
                // Notifications are silently ignored (per JSON-RPC spec)
                break;
        }
    }

    private static async Task HandleInitializeAsync(JsonRpcMessage message)
    {
        // Cache editor's initialize params for forwarding to agents
        CachedInitializeParams = message.Params?.DeepClone();

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

        await Output.EnqueueAsync(response);
    }

    private static async Task HandleSessionNewAsync(JsonRpcMessage message, string agent)
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
        var workspace = await ResolveWorkspaceRootAsync(originalCwd);

        // Create session
        var session = new Session(workspace);

        try
        {
            // Spawn agent process
            var process = SpawnAgentProcess(workspace, agent);
            session.AgentProcess = process;

            // Start reader task FIRST to handle out-of-order responses and notifications
            session.ReaderTask = Task.Run(() => ReadAgentOutputAsync(session));

            // Build initialize request for agent (forward editor's params)
            var initParams = new JsonObject
            {
                ["protocolVersion"] = "2025-01-01"
            };
            if (CachedInitializeParams is JsonObject cachedParams)
            {
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

            var initRequestId = "init-" + session.ProxySessionId;
            var initRequest = new JsonRpcMessage
            {
                Id = initRequestId,
                Method = "initialize",
                Params = initParams
            };
            await session.WriteToAgentAsync(initRequest);

            // Wait for initialize response (with timeout)
            var initResponse = await session.WaitForResponseAsync(initRequestId, TimeSpan.FromSeconds(30));
            if (initResponse == null)
            {
                throw new Exception("Agent did not respond to initialize");
            }

            // Calculate container cwd - preserve relative path from workspace root
            var containerCwd = "/home/agent/workspace";
            var normalizedWorkspace = Path.GetFullPath(workspace).TrimEnd(Path.DirectorySeparatorChar);
            var normalizedOriginalCwd = Path.GetFullPath(originalCwd).TrimEnd(Path.DirectorySeparatorChar);

            if (normalizedOriginalCwd != normalizedWorkspace)
            {
                var prefix = normalizedWorkspace + Path.DirectorySeparatorChar;
                if (normalizedOriginalCwd.StartsWith(prefix, StringComparison.Ordinal))
                {
                    var relativePath = normalizedOriginalCwd.Substring(prefix.Length);
                    containerCwd = "/home/agent/workspace/" + relativePath.Replace(Path.DirectorySeparatorChar, '/');
                }
            }

            // Create session/new request for agent
            var sessionNewParams = new JsonObject
            {
                ["cwd"] = containerCwd
            };

            // Translate MCP server args if provided
            if (mcpServersNode is JsonObject mcpServers)
            {
                var translatedMcp = TranslateMcpServers(mcpServers, workspace);
                sessionNewParams["mcpServers"] = translatedMcp;
            }

            var sessionNewRequestId = "session-new-" + session.ProxySessionId;
            var sessionNewRequest = new JsonRpcMessage
            {
                Id = sessionNewRequestId,
                Method = "session/new",
                Params = sessionNewParams
            };
            await session.WriteToAgentAsync(sessionNewRequest);

            // Wait for session/new response
            var sessionNewResponse = await session.WaitForResponseAsync(sessionNewRequestId, TimeSpan.FromSeconds(30));
            if (sessionNewResponse == null)
            {
                throw new Exception("Agent did not respond to session/new");
            }

            // Extract agent's session ID
            if (sessionNewResponse.Result is JsonObject resultObj &&
                resultObj.TryGetPropertyValue("sessionId", out var sessionIdNode))
            {
                session.AgentSessionId = sessionIdNode?.GetValue<string>() ?? "";
            }

            // Register session
            Sessions[session.ProxySessionId] = session;

            // Respond to editor with proxy session ID
            var response = new JsonRpcMessage
            {
                Id = message.Id,
                Result = new JsonObject
                {
                    ["sessionId"] = session.ProxySessionId
                }
            };
            await Output.EnqueueAsync(response);
        }
        catch (Exception ex)
        {
            // Clean up on failure
            session.Dispose();

            // Only respond if this was a request (has id)
            if (message.Id != null)
            {
                await Output.EnqueueAsync(new JsonRpcMessage
                {
                    Id = message.Id,
                    Error = new JsonRpcError
                    {
                        Code = -32000,
                        Message = $"Failed to create session: {ex.Message}"
                    }
                });
            }
        }
    }

    private static async Task RouteToSessionAsync(JsonRpcMessage message)
    {
        // Extract sessionId from params
        string? sessionId = null;
        if (message.Params is JsonObject paramsObj &&
            paramsObj.TryGetPropertyValue("sessionId", out var sessionIdNode))
        {
            sessionId = sessionIdNode?.GetValue<string>();
        }

        if (string.IsNullOrEmpty(sessionId) || !Sessions.TryGetValue(sessionId, out var session))
        {
            // Only respond with error if this is a request (has id)
            if (message.Id != null)
            {
                await Output.EnqueueAsync(new JsonRpcMessage
                {
                    Id = message.Id,
                    Error = new JsonRpcError
                    {
                        Code = -32001,
                        Message = $"Session not found: {sessionId}"
                    }
                });
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

    private static async Task HandleSessionEndAsync(string sessionId, JsonRpcMessage message)
    {
        if (!Sessions.TryRemove(sessionId, out var session))
            return;

        try
        {
            // Forward session/end to agent with agent's sessionId
            var endRequest = new JsonRpcMessage
            {
                Id = message.Id,
                Method = "session/end",
                Params = new JsonObject
                {
                    ["sessionId"] = session.AgentSessionId
                }
            };
            await session.WriteToAgentAsync(endRequest);

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
            await Output.EnqueueAsync(new JsonRpcMessage
            {
                Id = message.Id,
                Result = new JsonObject { }
            });
        }
    }

    private static async Task ReadAgentOutputAsync(Session session)
    {
        try
        {
            var reader = session.AgentProcess?.StandardOutput;
            if (reader == null)
                return;

            string? line;
            while ((line = await reader.ReadLineAsync()) != null)
            {
                if (string.IsNullOrWhiteSpace(line))
                    continue;

                try
                {
                    var message = JsonSerializer.Deserialize(line, AcpJsonContext.Default.JsonRpcMessage);
                    if (message == null)
                        continue;

                    // Check if this is a response to a pending request
                    if (message.Id != null && (message.Result != null || message.Error != null))
                    {
                        var idStr = message.Id.ToString();
                        if (session.TryCompleteResponse(idStr, message))
                        {
                            // Response was consumed by a waiter
                            continue;
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
                    await Output.EnqueueAsync(message);
                }
                catch (JsonException)
                {
                    // Skip malformed messages
                }
            }
        }
        catch (Exception ex)
        {
            await Console.Error.WriteLineAsync($"Agent reader error for session {session.ProxySessionId}: {ex.Message}");
        }
    }

    private static async Task ShutdownAsync()
    {
        // End all sessions gracefully
        foreach (var sessionId in Sessions.Keys.ToList())
        {
            if (Sessions.TryRemove(sessionId, out var session))
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

    private static Process SpawnAgentProcess(string workspace, string agent)
    {
        var directSpawn = Environment.GetEnvironmentVariable("CAI_ACP_DIRECT_SPAWN") == "1";

        Process? process;
        if (directSpawn)
        {
            var psi = new ProcessStartInfo
            {
                FileName = agent,
                RedirectStandardInput = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true,
            };
            psi.ArgumentList.Add("--acp");
            process = Process.Start(psi);
        }
        else
        {
            var psi = new ProcessStartInfo
            {
                FileName = "cai",
                RedirectStandardInput = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true,
            };
            // Use ArgumentList to safely pass arguments without quoting issues
            psi.ArgumentList.Add("exec");
            psi.ArgumentList.Add("--workspace");
            psi.ArgumentList.Add(workspace);
            psi.ArgumentList.Add("--quiet");
            psi.ArgumentList.Add("--");
            psi.ArgumentList.Add(agent);
            psi.ArgumentList.Add("--acp");

            // Prevent stdout pollution from child cai processes
            psi.Environment["CAI_NO_UPDATE_CHECK"] = "1";

            process = Process.Start(psi);
        }

        if (process == null)
        {
            throw new Exception($"Failed to start agent process: {agent}");
        }

        // Forward stderr to our stderr
        _ = Task.Run(async () =>
        {
            try
            {
                var errReader = process.StandardError;
                string? line;
                while ((line = await errReader.ReadLineAsync()) != null)
                {
                    await Console.Error.WriteLineAsync(line);
                }
            }
            catch { }
        });

        return process;
    }

    private static async Task<string> ResolveWorkspaceRootAsync(string cwd)
    {
        // Try git root first
        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = "git",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true,
            };
            psi.ArgumentList.Add("-C");
            psi.ArgumentList.Add(cwd);
            psi.ArgumentList.Add("rev-parse");
            psi.ArgumentList.Add("--show-toplevel");

            using var process = Process.Start(psi);
            if (process != null)
            {
                var output = await process.StandardOutput.ReadToEndAsync();
                await process.WaitForExitAsync();

                if (process.ExitCode == 0 && !string.IsNullOrWhiteSpace(output))
                {
                    return output.Trim();
                }
            }
        }
        catch { }

        // Walk up looking for .containai/config.toml
        var dir = new DirectoryInfo(cwd);
        while (dir != null)
        {
            var configPath = Path.Combine(dir.FullName, ".containai", "config.toml");
            if (File.Exists(configPath))
            {
                return dir.FullName;
            }
            dir = dir.Parent;
        }

        // Fall back to cwd
        return cwd;
    }

    private static JsonObject TranslateMcpServers(JsonObject mcpServers, string hostWorkspace)
    {
        var containerPath = "/home/agent/workspace";
        var normalizedWorkspace = Path.GetFullPath(hostWorkspace).TrimEnd(Path.DirectorySeparatorChar);

        var result = new JsonObject();

        foreach (var (serverName, serverConfig) in mcpServers)
        {
            if (serverConfig is not JsonObject serverObj)
            {
                result[serverName] = serverConfig?.DeepClone();
                continue;
            }

            var translatedServer = new JsonObject();

            foreach (var (key, value) in serverObj)
            {
                if (key == "args" && value is JsonArray argsArray)
                {
                    // Translate args
                    var translatedArgs = new JsonArray();
                    foreach (var arg in argsArray)
                    {
                        if (arg is JsonValue argValue && argValue.TryGetValue<string>(out var argStr))
                        {
                            // Cast to JsonNode to avoid generic Add<T> warnings with AOT
                            translatedArgs.Add((JsonNode)JsonValue.Create(TranslatePath(argStr, normalizedWorkspace, containerPath))!);
                        }
                        else
                        {
                            translatedArgs.Add(arg?.DeepClone());
                        }
                    }
                    translatedServer[key] = translatedArgs;
                }
                else
                {
                    translatedServer[key] = value?.DeepClone();
                }
            }

            result[serverName] = translatedServer;
        }

        return result;
    }

    private static string TranslatePath(string arg, string normalizedWorkspace, string containerPath)
    {
        // Only translate absolute paths
        if (!Path.IsPathRooted(arg))
        {
            return arg;
        }

        // Normalize the arg
        string normalizedArg;
        try
        {
            normalizedArg = Path.GetFullPath(arg).TrimEnd(Path.DirectorySeparatorChar);
        }
        catch
        {
            return arg; // Invalid path format
        }

        // Exact match
        if (normalizedArg == normalizedWorkspace)
        {
            return containerPath;
        }

        // Descendant match
        var prefix = normalizedWorkspace + Path.DirectorySeparatorChar;
        if (normalizedArg.StartsWith(prefix, StringComparison.Ordinal))
        {
            var relative = normalizedArg.Substring(prefix.Length);
            return containerPath + "/" + relative.Replace(Path.DirectorySeparatorChar, '/');
        }

        // Not a workspace path
        return arg;
    }
}

public class Session : IDisposable
{
    public string ProxySessionId { get; } = Guid.NewGuid().ToString();
    public string AgentSessionId { get; set; } = "";
    public string Workspace { get; }
    public Process? AgentProcess { get; set; }
    public Task? ReaderTask { get; set; }

    private readonly SemaphoreSlim _writeLock = new(1, 1);
    private readonly ConcurrentDictionary<string, TaskCompletionSource<JsonRpcMessage>> _pendingRequests = new();

    public Session(string workspace)
    {
        Workspace = workspace;
    }

    public async Task WriteToAgentAsync(JsonRpcMessage message)
    {
        if (AgentProcess?.StandardInput == null)
            return;

        await _writeLock.WaitAsync();
        try
        {
            var json = JsonSerializer.Serialize(message, AcpJsonContext.Default.JsonRpcMessage);
            await AgentProcess.StandardInput.WriteLineAsync(json);
            await AgentProcess.StandardInput.FlushAsync();
        }
        finally
        {
            _writeLock.Release();
        }
    }

    public async Task<JsonRpcMessage?> WaitForResponseAsync(string requestId, TimeSpan timeout)
    {
        var tcs = new TaskCompletionSource<JsonRpcMessage>(TaskCreationOptions.RunContinuationsAsynchronously);
        _pendingRequests[requestId] = tcs;

        try
        {
            using var cts = new CancellationTokenSource(timeout);
            var completedTask = await Task.WhenAny(tcs.Task, Task.Delay(Timeout.Infinite, cts.Token));
            if (completedTask == tcs.Task)
            {
                return await tcs.Task;
            }
            return null; // Timeout
        }
        finally
        {
            _pendingRequests.TryRemove(requestId, out _);
        }
    }

    public bool TryCompleteResponse(string requestId, JsonRpcMessage response)
    {
        if (_pendingRequests.TryRemove(requestId, out var tcs))
        {
            tcs.TrySetResult(response);
            return true;
        }
        return false;
    }

    public void Dispose()
    {
        // Cancel any pending requests
        foreach (var tcs in _pendingRequests.Values)
        {
            tcs.TrySetCanceled();
        }
        _pendingRequests.Clear();

        try
        {
            AgentProcess?.Kill();
        }
        catch { }
        AgentProcess?.Dispose();
        _writeLock.Dispose();
    }
}

public class OutputWriter
{
    private readonly Channel<JsonRpcMessage> _channel = Channel.CreateUnbounded<JsonRpcMessage>();
    private readonly Stream _stdout;

    public OutputWriter(Stream stdout)
    {
        _stdout = stdout;
    }

    public async Task EnqueueAsync(JsonRpcMessage message)
    {
        await _channel.Writer.WriteAsync(message);
    }

    public void Complete()
    {
        _channel.Writer.Complete();
    }

    public async Task RunAsync(CancellationToken ct)
    {
        try
        {
            await foreach (var message in _channel.Reader.ReadAllAsync(ct))
            {
                var json = JsonSerializer.Serialize(message, AcpJsonContext.Default.JsonRpcMessage);
                var bytes = Encoding.UTF8.GetBytes(json + "\n");
                await _stdout.WriteAsync(bytes, ct);
                await _stdout.FlushAsync(ct);
            }
        }
        catch (OperationCanceledException)
        {
            // Expected during shutdown
        }
    }
}

public class JsonRpcMessage
{
    [JsonPropertyName("jsonrpc")]
    public string JsonRpc { get; set; } = "2.0";

    // Id can be string or number in JSON-RPC, use JsonNode to preserve type
    [JsonPropertyName("id")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public JsonNode? Id { get; set; }

    [JsonPropertyName("method")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? Method { get; set; }

    [JsonPropertyName("params")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public JsonNode? Params { get; set; }

    [JsonPropertyName("result")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public JsonNode? Result { get; set; }

    [JsonPropertyName("error")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public JsonRpcError? Error { get; set; }
}

public class JsonRpcError
{
    [JsonPropertyName("code")]
    public int Code { get; set; }

    [JsonPropertyName("message")]
    public string Message { get; set; } = "";

    [JsonPropertyName("data")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public JsonNode? Data { get; set; }
}

// JSON Source Generator for AOT compatibility
[JsonSourceGenerationOptions(
    PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase,
    DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull)]
[JsonSerializable(typeof(JsonRpcMessage))]
[JsonSerializable(typeof(JsonRpcError))]
internal partial class AcpJsonContext : JsonSerializerContext
{
}

public static class JsonOptions
{
    public static readonly JsonSerializerOptions Default = AcpJsonContext.Default.Options;
}
