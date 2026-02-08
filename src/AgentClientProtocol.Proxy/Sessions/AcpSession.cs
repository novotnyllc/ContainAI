// ACP session management
using System.Collections.Concurrent;
using System.Text.Json;
using System.Threading.Channels;
using AgentClientProtocol.Proxy.Protocol;

namespace AgentClientProtocol.Proxy.Sessions;

/// <summary>
/// Represents an ACP session with an agent process.
/// </summary>
public sealed class AcpSession : IDisposable
{
    private readonly SemaphoreSlim _writeLock = new(1, 1);
    private readonly ConcurrentDictionary<string, TaskCompletionSource<JsonRpcMessage>> _pendingRequests = new();
    private readonly CancellationTokenSource _cts = new();
    private ChannelWriter<string>? _agentInput;
    private bool _disposed;

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
    public CancellationToken CancellationToken => _cts.Token;

    public AcpSession(string workspace) => Workspace = workspace;

    internal void AttachAgentTransport(
        ChannelWriter<string> input,
        ChannelReader<string> output,
        Task executionTask)
    {
        ArgumentNullException.ThrowIfNull(input);
        ArgumentNullException.ThrowIfNull(output);
        ArgumentNullException.ThrowIfNull(executionTask);

        _agentInput = input;
        AgentOutput = output;
        AgentExecutionTask = executionTask;
    }

    /// <summary>
    /// Writes a JSON-RPC message to the agent.
    /// </summary>
    public async Task WriteToAgentAsync(JsonRpcMessage message)
    {
        if (_agentInput == null)
            return;

        await _writeLock.WaitAsync().ConfigureAwait(false);
        try
        {
            var json = JsonSerializer.Serialize(message, AcpJsonContext.Default.JsonRpcMessage);
            await _agentInput.WriteAsync(json, _cts.Token).ConfigureAwait(false);
        }
        catch (ChannelClosedException)
        {
            // Agent transport already closed.
        }
        finally
        {
            _writeLock.Release();
        }
    }

    /// <summary>
    /// Registers a pending request, sends it, then waits for the response.
    /// This avoids race conditions where the response arrives before WaitForResponseAsync is called.
    /// </summary>
    public async Task<JsonRpcMessage?> SendAndWaitForResponseAsync(
        JsonRpcMessage request,
        string requestId,
        TimeSpan timeout)
    {
        var tcs = new TaskCompletionSource<JsonRpcMessage>(TaskCreationOptions.RunContinuationsAsynchronously);

        // Register BEFORE sending to avoid race condition
        _pendingRequests[requestId] = tcs;

        try
        {
            // Send the request
            await WriteToAgentAsync(request).ConfigureAwait(false);

            // Wait for response with timeout
            using var cts = CancellationTokenSource.CreateLinkedTokenSource(_cts.Token);
            cts.CancelAfter(timeout);

            try
            {
                if (AgentExecutionTask == null)
                {
                    return await tcs.Task.WaitAsync(cts.Token).ConfigureAwait(false);
                }

                var cancellationTask = Task.Delay(Timeout.InfiniteTimeSpan, cts.Token);
                var completed = await Task
                    .WhenAny(tcs.Task, AgentExecutionTask, cancellationTask)
                    .ConfigureAwait(false);
                if (completed == tcs.Task)
                {
                    return await tcs.Task.ConfigureAwait(false);
                }

                return null;
            }
            catch (OperationCanceledException)
            {
                return null; // Timeout or session cancelled
            }
        }
        finally
        {
            _pendingRequests.TryRemove(requestId, out _);
        }
    }

    /// <summary>
    /// Attempts to complete a pending request with a response.
    /// Returns true if the response was matched to a pending request.
    /// </summary>
    public bool TryCompleteResponse(string requestId, JsonRpcMessage response)
    {
        if (_pendingRequests.TryRemove(requestId, out var tcs))
        {
            tcs.TrySetResult(response);
            return true;
        }
        return false;
    }

    /// <summary>
    /// Signals that the session should stop.
    /// </summary>
    public void Cancel()
    {
        if (!_disposed)
        {
            _cts.Cancel();
        }
    }

    public void Dispose()
    {
        if (_disposed)
            return;
        _disposed = true;

        // Cancel any pending requests
        foreach (var tcs in _pendingRequests.Values)
        {
            tcs.TrySetCanceled();
        }
        _pendingRequests.Clear();

        // Cancel the session
        _cts.Cancel();
        _cts.Dispose();

        _agentInput?.TryComplete();

        _writeLock.Dispose();
    }
}
