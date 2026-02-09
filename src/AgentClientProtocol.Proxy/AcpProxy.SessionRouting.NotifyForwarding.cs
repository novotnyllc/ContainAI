using System.Text.Json;
using AgentClientProtocol.Proxy.Protocol;
using AgentClientProtocol.Proxy.Sessions;

namespace AgentClientProtocol.Proxy;

public sealed partial class AcpProxy
{
    private async Task ReadAgentOutputLoopAsync(AcpSession session)
    {
        try
        {
            var sessionOutput = session.AgentOutput;
            if (sessionOutput == null)
            {
                return;
            }

            await foreach (var line in sessionOutput.ReadAllAsync(session.CancellationToken).ConfigureAwait(false))
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
        {
            return;
        }

        try
        {
            var message = JsonSerializer.Deserialize(line, AcpJsonContext.Default.JsonRpcEnvelope);
            if (message == null)
            {
                return;
            }

            if (message.Id != null && (message.Result != null || message.Error != null))
            {
                var idStr = JsonRpcHelpers.NormalizeId(message.Id);
                if (idStr != null && session.TryCompleteResponse(idStr, message))
                {
                    return;
                }
            }

            var scopedParams = DeserializeElement(message.Params, AcpJsonContext.Default.SessionScopedParams);
            if (scopedParams is not null && scopedParams.SessionId == session.AgentSessionId)
            {
                scopedParams.SessionId = session.ProxySessionId;
                message.Params = SerializeElement(scopedParams, AcpJsonContext.Default.SessionScopedParams);
            }

            await output.EnqueueAsync(message).ConfigureAwait(false);
        }
        catch (JsonException ex)
        {
            await errorSink.WriteLineAsync($"Malformed agent output skipped for session {session.ProxySessionId}: {ex.Message}").ConfigureAwait(false);
        }
    }
}
