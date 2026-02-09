using AgentClientProtocol.Proxy.Protocol;

namespace AgentClientProtocol.Proxy;

public sealed partial class AcpProxy
{
    private async Task HandleSessionEndAsync(string sessionId, JsonRpcEnvelope message)
    {
        if (!sessions.TryRemove(sessionId, out var session))
        {
            return;
        }

        try
        {
            var endNotification = new JsonRpcEnvelope
            {
                Method = "session/end",
                Params = SerializeElement(
                    new SessionScopedParams { SessionId = session.AgentSessionId },
                    AcpJsonContext.Default.SessionScopedParams),
            };
            await session.WriteToAgentAsync(endNotification).ConfigureAwait(false);

            using var shutdownCts = new CancellationTokenSource(TimeSpan.FromSeconds(5));
            try
            {
                if (session.ReaderTask != null)
                {
                    await session.ReaderTask.WaitAsync(shutdownCts.Token).ConfigureAwait(false);
                }
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

    private async Task ShutdownAsync()
    {
        foreach (var sessionId in sessions.Keys.ToList())
        {
            if (!sessions.TryRemove(sessionId, out var session))
            {
                continue;
            }

            try
            {
                var endRequest = new JsonRpcEnvelope
                {
                    Method = "session/end",
                    Params = SerializeElement(
                        new SessionScopedParams { SessionId = session.AgentSessionId },
                        AcpJsonContext.Default.SessionScopedParams),
                };
                await session.WriteToAgentAsync(endRequest).ConfigureAwait(false);

                using var shutdownCts = new CancellationTokenSource(TimeSpan.FromSeconds(2));
                try
                {
                    if (session.ReaderTask != null)
                    {
                        await session.ReaderTask.WaitAsync(shutdownCts.Token).ConfigureAwait(false);
                    }
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
