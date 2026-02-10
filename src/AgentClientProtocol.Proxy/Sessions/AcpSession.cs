// ACP session management
using System.Threading.Channels;
using AgentClientProtocol.Proxy.Protocol;

namespace AgentClientProtocol.Proxy.Sessions;

/// <summary>
/// Represents an ACP session with an agent process.
/// </summary>
public sealed class AcpSession : IDisposable
{
    private readonly CancellationTokenSource cts = new();
    private readonly AcpSessionTransport transport;
    private readonly AcpPendingRequestRegistry pendingRequestRegistry;
    private bool disposed;

    /// <summary>
    /// The proxy-assigned session ID (exposed to editors).
    /// </summary>
    public string ProxySessionId { get; } = Guid.NewGuid().ToString();

    /// <summary>
    /// The agent-assigned session ID (used for routing to agent).
    /// </summary>
    public string AgentSessionId { get; set; } = "";

    /// <summary>
    /// The workspace path this session is associated with.
    /// </summary>
    public string Workspace { get; }

    public ChannelReader<string>? AgentOutput { get; private set; }

    public Task? AgentExecutionTask { get; private set; }

    /// <summary>
    /// Task that reads from the agent's stdout.
    /// </summary>
    public Task? ReaderTask { get; set; }

    /// <summary>
    /// Cancellation token for this session.
    /// </summary>
    public CancellationToken CancellationToken => cts.Token;

    public AcpSession(string workspace)
    {
        Workspace = workspace;
        transport = new AcpSessionTransport(cts);
        pendingRequestRegistry = new AcpPendingRequestRegistry(cts);
    }

    internal void AttachAgentTransport(
        ChannelWriter<string> input,
        ChannelReader<string> output,
        Task executionTask)
    {
        transport.Attach(input, output, executionTask);
        AgentOutput = transport.AgentOutput;
        AgentExecutionTask = transport.AgentExecutionTask;
    }

    /// <summary>
    /// Writes a JSON-RPC message to the agent.
    /// </summary>
    public Task WriteToAgentAsync(JsonRpcEnvelope message) => transport.WriteAsync(message);

    /// <summary>
    /// Registers a pending request, sends it, then waits for the response.
    /// This avoids race conditions where the response arrives before WaitForResponseAsync is called.
    /// </summary>
    public Task<JsonRpcEnvelope?> SendAndWaitForResponseAsync(
        JsonRpcEnvelope request,
        string requestId,
        TimeSpan timeout) => pendingRequestRegistry.SendAndWaitForResponseAsync(
                request,
                requestId,
                timeout,
                WriteToAgentAsync,
                AgentExecutionTask);

    /// <summary>
    /// Attempts to complete a pending request with a response.
    /// Returns true if the response was matched to a pending request.
    /// </summary>
    public bool TryCompleteResponse(string requestId, JsonRpcEnvelope response)
        => pendingRequestRegistry.TryCompleteResponse(requestId, response);

    /// <summary>
    /// Signals that the session should stop.
    /// </summary>
    public void Cancel()
    {
        if (!disposed)
        {
            cts.Cancel();
        }
    }

    public void Dispose()
    {
        if (disposed)
            return;
        disposed = true;

        pendingRequestRegistry.CancelPendingRequests();

        // Cancel the session
        cts.Cancel();
        cts.Dispose();

        transport.CompleteInput();
        transport.Dispose();
    }
}
