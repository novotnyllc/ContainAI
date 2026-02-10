using System.Collections.Concurrent;
using AgentClientProtocol.Proxy.Protocol;

namespace AgentClientProtocol.Proxy.Sessions;

internal sealed class AcpPendingRequestRegistry
{
    private readonly ConcurrentDictionary<string, TaskCompletionSource<JsonRpcEnvelope>> pendingRequests = new();
    private readonly CancellationTokenSource cts;

    public AcpPendingRequestRegistry(CancellationTokenSource cts)
    {
        ArgumentNullException.ThrowIfNull(cts);
        this.cts = cts;
    }

    public async Task<JsonRpcEnvelope?> SendAndWaitForResponseAsync(
        JsonRpcEnvelope request,
        string requestId,
        TimeSpan timeout,
        Func<JsonRpcEnvelope, Task> sendAsync,
        Task? agentExecutionTask)
    {
        var tcs = new TaskCompletionSource<JsonRpcEnvelope>(TaskCreationOptions.RunContinuationsAsynchronously);

        // Register BEFORE sending to avoid race condition.
        pendingRequests[requestId] = tcs;

        try
        {
            // Send the request.
            await sendAsync(request).ConfigureAwait(false);

            // Wait for response with timeout.
            using var timeoutCts = CancellationTokenSource.CreateLinkedTokenSource(cts.Token);
            timeoutCts.CancelAfter(timeout);

            try
            {
                if (agentExecutionTask == null)
                {
                    return await tcs.Task.WaitAsync(timeoutCts.Token).ConfigureAwait(false);
                }

                var cancellationTask = Task.Delay(Timeout.InfiniteTimeSpan, timeoutCts.Token);
                var completed = await Task
                    .WhenAny(tcs.Task, agentExecutionTask, cancellationTask)
                    .ConfigureAwait(false);
                if (completed == tcs.Task)
                {
                    return await tcs.Task.ConfigureAwait(false);
                }

                return null;
            }
            catch (OperationCanceledException)
            {
                return null; // Timeout or session cancelled.
            }
        }
        finally
        {
            pendingRequests.TryRemove(requestId, out _);
        }
    }

    public bool TryCompleteResponse(string requestId, JsonRpcEnvelope response)
    {
        if (pendingRequests.TryRemove(requestId, out var tcs))
        {
            tcs.TrySetResult(response);
            return true;
        }

        return false;
    }

    public void CancelPendingRequests()
    {
        foreach (var tcs in pendingRequests.Values)
        {
            tcs.TrySetCanceled();
        }

        pendingRequests.Clear();
    }
}
