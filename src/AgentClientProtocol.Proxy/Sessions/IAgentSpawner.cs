namespace AgentClientProtocol.Proxy.Sessions;

/// <summary>
/// Creates and starts ACP agent processes for sessions.
/// </summary>
public interface IAgentSpawner
{
    Task SpawnAgentAsync(AcpSession session, string agent, CancellationToken cancellationToken = default);
}
