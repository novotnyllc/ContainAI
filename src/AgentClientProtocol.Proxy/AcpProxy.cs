using System.Collections.Concurrent;
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
    /// Signals the proxy to stop.
    /// </summary>
    public void Cancel() => cts.Cancel();

    public void Dispose() => cts.Dispose();

    private sealed class ErrorSink(TextWriter writer)
    {
        public ValueTask WriteLineAsync(string message)
            => new(writer.WriteLineAsync(message));
    }
}
