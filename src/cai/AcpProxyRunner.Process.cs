using AgentClientProtocol.Proxy;

namespace ContainAI.Cli.Host;

internal interface IAcpProxyProcess : IDisposable
{
    void Cancel();

    Task<int> RunAsync(Stream stdin, CancellationToken cancellationToken);
}

internal sealed class AcpProxyProcessAdapter : IAcpProxyProcess
{
    private readonly AcpProxy proxy;

    public AcpProxyProcessAdapter(
        string agent,
        Stream stdout,
        TextWriter stderr) => proxy = new AcpProxy(agent, stdout, stderr);

    public void Cancel() => proxy.Cancel();

    public Task<int> RunAsync(Stream stdin, CancellationToken cancellationToken) => proxy.RunAsync(stdin, cancellationToken);

    public void Dispose() => proxy.Dispose();
}
