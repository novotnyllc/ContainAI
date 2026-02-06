using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed class CaiCommandRuntime : ICaiCommandRuntime
{
    private readonly ILegacyContainAiBridge _legacyBridge;
    private readonly AcpProxyRunner _acpProxyRunner;

    public CaiCommandRuntime(ILegacyContainAiBridge legacyBridge, AcpProxyRunner acpProxyRunner)
    {
        _legacyBridge = legacyBridge;
        _acpProxyRunner = acpProxyRunner;
    }

    public Task<int> RunLegacyAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => _legacyBridge.InvokeAsync(args, cancellationToken);

    public Task<int> RunAcpProxyAsync(string agent, CancellationToken cancellationToken)
        => _acpProxyRunner.RunAsync(agent, cancellationToken);
}
