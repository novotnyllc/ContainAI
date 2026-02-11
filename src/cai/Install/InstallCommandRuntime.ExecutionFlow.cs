using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal interface IInstallCommandExecution
{
    Task<int> RunAsync(InstallCommandOptions options, CancellationToken cancellationToken);
}

internal sealed partial class InstallCommandExecution : IInstallCommandExecution
{
    private readonly IInstallPathResolver pathResolver;
    private readonly IInstallDeploymentService deploymentService;
    private readonly IInstallAssetMaterializer assetMaterializer;
    private readonly IInstallCommandOutput output;
    private readonly IInstallShellIntegrationUpdater shellIntegrationUpdater;
    private readonly IInstallSetupRunner setupRunner;

    public InstallCommandExecution(
        IInstallPathResolver pathResolver,
        IInstallDeploymentService deploymentService,
        IInstallAssetMaterializer assetMaterializer,
        IInstallCommandOutput output,
        IInstallShellIntegrationUpdater shellIntegrationUpdater,
        IInstallSetupRunner setupRunner)
    {
        this.pathResolver = pathResolver ?? throw new ArgumentNullException(nameof(pathResolver));
        this.deploymentService = deploymentService ?? throw new ArgumentNullException(nameof(deploymentService));
        this.assetMaterializer = assetMaterializer ?? throw new ArgumentNullException(nameof(assetMaterializer));
        this.output = output ?? throw new ArgumentNullException(nameof(output));
        this.shellIntegrationUpdater = shellIntegrationUpdater ?? throw new ArgumentNullException(nameof(shellIntegrationUpdater));
        this.setupRunner = setupRunner ?? throw new ArgumentNullException(nameof(setupRunner));
    }

}
