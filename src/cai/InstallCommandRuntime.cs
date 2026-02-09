namespace ContainAI.Cli.Host;

internal sealed partial class InstallCommandRuntime
{
    private readonly IInstallPathResolver pathResolver;
    private readonly IInstallDeploymentService deploymentService;
    private readonly IInstallAssetMaterializer assetMaterializer;
    private readonly IShellProfileIntegration shellProfileIntegration;
    private readonly TextWriter stderr;
    private readonly TextWriter stdout;

    public InstallCommandRuntime(
        IInstallPathResolver? pathResolver = null,
        IInstallDeploymentService? deploymentService = null,
        IInstallAssetMaterializer? assetMaterializer = null,
        IShellProfileIntegration? shellProfileIntegration = null,
        TextWriter? standardOutput = null,
        TextWriter? standardError = null)
    {
        this.pathResolver = pathResolver ?? new InstallPathResolver();
        this.deploymentService = deploymentService ?? new InstallDeploymentService();
        this.assetMaterializer = assetMaterializer ?? new InstallAssetMaterializer();
        this.shellProfileIntegration = shellProfileIntegration ?? new ShellProfileIntegrationService();
        stdout = standardOutput ?? Console.Out;
        stderr = standardError ?? Console.Error;
    }
}
