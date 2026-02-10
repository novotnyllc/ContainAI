using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed class InstallCommandRuntime
{
    private readonly IInstallCommandExecution commandExecution;

    public InstallCommandRuntime(
        IInstallPathResolver? pathResolver = null,
        IInstallDeploymentService? deploymentService = null,
        IInstallAssetMaterializer? assetMaterializer = null,
        IShellProfileIntegration? shellProfileIntegration = null,
        TextWriter? standardOutput = null,
        TextWriter? standardError = null)
        : this(
            pathResolver ?? new InstallPathResolver(),
            deploymentService ?? new InstallDeploymentService(),
            assetMaterializer ?? new InstallAssetMaterializer(),
            shellProfileIntegration ?? new ShellProfileIntegrationService(),
            new InstallCommandOutput(
                standardOutput ?? Console.Out,
                standardError ?? Console.Error))
    {
    }

    internal InstallCommandRuntime(
        IInstallPathResolver pathResolver,
        IInstallDeploymentService deploymentService,
        IInstallAssetMaterializer assetMaterializer,
        IShellProfileIntegration shellProfileIntegration,
        IInstallCommandOutput output,
        IInstallShellIntegrationUpdater? shellIntegrationUpdater = null,
        IInstallSetupRunner? setupRunner = null,
        IInstallCommandExecution? commandExecution = null)
    {
        ArgumentNullException.ThrowIfNull(pathResolver);
        ArgumentNullException.ThrowIfNull(deploymentService);
        ArgumentNullException.ThrowIfNull(assetMaterializer);
        ArgumentNullException.ThrowIfNull(shellProfileIntegration);
        ArgumentNullException.ThrowIfNull(output);

        var effectiveShellIntegrationUpdater = shellIntegrationUpdater
            ?? new InstallShellIntegrationUpdater(pathResolver, shellProfileIntegration, output);
        var effectiveSetupRunner = setupRunner ?? new InstallSetupRunner(output);

        this.commandExecution = commandExecution
            ?? new InstallCommandExecution(
                pathResolver,
                deploymentService,
                assetMaterializer,
                output,
                effectiveShellIntegrationUpdater,
                effectiveSetupRunner);
    }

    public Task<int> RunAsync(InstallCommandOptions options, CancellationToken cancellationToken)
        => commandExecution.RunAsync(options, cancellationToken);
}
