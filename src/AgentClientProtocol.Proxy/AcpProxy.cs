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
/// and routes to agent processes over ACP.
/// </summary>
public sealed partial class AcpProxy : IDisposable
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
    /// <param name="agentSpawner">Optional custom agent spawner. If null, default spawner is used.</param>
    public AcpProxy(
        string agentName,
        Stream outputStream,
        TextWriter errorWriter,
        IAgentSpawner? customAgentSpawner = null)
    {
        ArgumentNullException.ThrowIfNull(agentName);
        ArgumentNullException.ThrowIfNull(outputStream);
        ArgumentNullException.ThrowIfNull(errorWriter);

        agent = agentName;
        output = new OutputWriter(outputStream);
        errorSink = new ErrorSink(errorWriter);
        agentSpawner = customAgentSpawner ?? new AgentSpawner(errorWriter);

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

        try
        {
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
        catch (JsonException ex)
        {
            if (message.Id != null)
            {
                await output.EnqueueAsync(JsonRpcHelpers.CreateErrorResponse(
                    message.Id,
                    JsonRpcErrorCodes.InvalidParams,
                    $"Invalid params: {ex.Message}")).ConfigureAwait(false);
                return;
            }

            await errorSink.WriteLineAsync($"Malformed notification params skipped: {ex.Message}").ConfigureAwait(false);
        }
    }

    public void Dispose() => cts.Dispose();

    private sealed class ErrorSink(TextWriter writer)
    {
        public ValueTask WriteLineAsync(string message)
            => new(writer.WriteLineAsync(message));
    }

}
