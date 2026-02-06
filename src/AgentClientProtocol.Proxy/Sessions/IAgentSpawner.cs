using System.Diagnostics;

namespace AgentClientProtocol.Proxy.Sessions;

/// <summary>
/// Creates and starts ACP agent processes for sessions.
/// </summary>
public interface IAgentSpawner
{
    Process SpawnAgent(AcpSession session, string agent);
}
