using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed class CaiRuntimeToolsCommandHandler
{
    private readonly AcpProxyRunner acpProxyRunner;
    private readonly InstallCommandRuntime installRuntime;
    private readonly ExamplesCommandRuntime examplesRuntime;

    public CaiRuntimeToolsCommandHandler(
        AcpProxyRunner proxyRunner,
        InstallCommandRuntime installCommandRuntime,
        ExamplesCommandRuntime examplesCommandRuntime)
    {
        acpProxyRunner = proxyRunner ?? throw new ArgumentNullException(nameof(proxyRunner));
        installRuntime = installCommandRuntime ?? throw new ArgumentNullException(nameof(installCommandRuntime));
        examplesRuntime = examplesCommandRuntime ?? throw new ArgumentNullException(nameof(examplesCommandRuntime));
    }

    public Task<int> RunAcpProxyAsync(string agent, CancellationToken cancellationToken)
        => acpProxyRunner.RunAsync(agent, cancellationToken);

    public Task<int> RunInstallAsync(InstallCommandOptions options, CancellationToken cancellationToken)
        => installRuntime.RunAsync(options, cancellationToken);

    public Task<int> RunExamplesListAsync(CancellationToken cancellationToken)
        => examplesRuntime.RunListAsync(cancellationToken);

    public Task<int> RunExamplesExportAsync(ExamplesExportCommandOptions options, CancellationToken cancellationToken)
        => examplesRuntime.RunExportAsync(options, cancellationToken);
}
