// ACP session management
using System.Collections.Concurrent;
using System.Diagnostics;
using System.Text.Json;
using ContainAI.Acp.Protocol;

namespace ContainAI.Acp.Sessions;

/// <summary>
/// Represents an ACP session with an agent process.
/// </summary>
public sealed class AcpSession : IDisposable
{
    private readonly SemaphoreSlim _writeLock = new(1, 1);
    private readonly ConcurrentDictionary<string, TaskCompletionSource<JsonRpcMessage>> _pendingRequests = new();
    private readonly CancellationTokenSource _cts = new();
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

    /// <summary>
    /// The agent process.
    /// </summary>
    public Process? AgentProcess { get; set; }

    /// <summary>
    /// Task that reads from the agent's stdout.
    /// </summary>
    public Task? ReaderTask { get; set; }

    /// <summary>
    /// Cancellation token for this session.
    /// </summary>
    public CancellationToken CancellationToken => _cts.Token;

    public AcpSession(string workspace) => Workspace = workspace;

    /// <summary>
    /// Writes a JSON-RPC message to the agent.
    /// </summary>
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
            await WriteToAgentAsync(request);

            // Wait for response with timeout
            using var cts = CancellationTokenSource.CreateLinkedTokenSource(_cts.Token);
            cts.CancelAfter(timeout);

            try
            {
                return await tcs.Task.WaitAsync(cts.Token);
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

        // Kill the process
        try
        {
            AgentProcess?.Kill();
        }
        catch
        {
            // Ignore errors killing process
        }
        AgentProcess?.Dispose();

        _writeLock.Dispose();
    }
}
