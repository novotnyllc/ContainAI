using AgentClientProtocol.Proxy.Protocol;

namespace AgentClientProtocol.Proxy;

public sealed partial class AcpProxy
{
    private async Task RouteToSessionAsync(JsonRpcEnvelope message)
    {
        var scopedParams = DeserializeElement(message.Params, AcpJsonContext.Default.SessionScopedParams);
        var sessionId = scopedParams?.SessionId;

        if (string.IsNullOrEmpty(sessionId) || !sessions.TryGetValue(sessionId, out var session))
        {
            if (message.Id != null)
            {
                await output.EnqueueAsync(JsonRpcHelpers.CreateErrorResponse(
                    message.Id,
                    JsonRpcErrorCodes.SessionNotFound,
                    $"Session not found: {sessionId}")).ConfigureAwait(false);
            }
            return;
        }

        if (message.Method == "session/end")
        {
            await HandleSessionEndAsync(sessionId, message).ConfigureAwait(false);
            return;
        }

        if (scopedParams != null)
        {
            scopedParams.SessionId = session.AgentSessionId;
            message.Params = SerializeElement(scopedParams, AcpJsonContext.Default.SessionScopedParams);
        }

        await session.WriteToAgentAsync(message).ConfigureAwait(false);
    }
}
