using AgentClientProtocol.Proxy;

namespace ContainAI.Cli.Host;

internal interface IAcpProxyProcess : IDisposable
{
    void Cancel();

    Task<int> RunAsync(Stream stdin, CancellationToken cancellationToken);
}
