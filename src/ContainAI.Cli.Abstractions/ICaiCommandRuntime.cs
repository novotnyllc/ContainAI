namespace ContainAI.Cli.Abstractions;

public interface ICaiCommandRuntime
{
    Task<int> RunLegacyAsync(IReadOnlyList<string> args, CancellationToken cancellationToken);

    Task<int> RunAcpProxyAsync(string agent, CancellationToken cancellationToken);
}
