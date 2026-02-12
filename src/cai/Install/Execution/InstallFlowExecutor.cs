namespace ContainAI.Cli.Host;

internal sealed class InstallFlowExecutor : IInstallFlowExecutor
{
    private readonly IInstallDeploymentService deploymentService;
    private readonly IInstallAssetMaterializer assetMaterializer;
    private readonly IInstallCommandOutput output;
    private readonly IInstallShellIntegrationUpdater shellIntegrationUpdater;
    private readonly IInstallSetupRunner setupRunner;

    public InstallFlowExecutor(
        IInstallDeploymentService installDeploymentService,
        IInstallAssetMaterializer installAssetMaterializer,
        IInstallCommandOutput installCommandOutput,
        IInstallShellIntegrationUpdater installShellIntegrationUpdater,
        IInstallSetupRunner installSetupRunner)
    {
        deploymentService = installDeploymentService ?? throw new ArgumentNullException(nameof(installDeploymentService));
        assetMaterializer = installAssetMaterializer ?? throw new ArgumentNullException(nameof(installAssetMaterializer));
        output = installCommandOutput ?? throw new ArgumentNullException(nameof(installCommandOutput));
        shellIntegrationUpdater = installShellIntegrationUpdater ?? throw new ArgumentNullException(nameof(installShellIntegrationUpdater));
        setupRunner = installSetupRunner ?? throw new ArgumentNullException(nameof(installSetupRunner));
    }

    public async Task<int> ExecuteAsync(InstallCommandContext context, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        var deployment = deploymentService.Deploy(context.SourceExecutablePath, context.InstallDir, context.BinDir);
        var assets = assetMaterializer.Materialize(context.InstallDir, context.HomeDirectory);

        await output.WriteSuccessAsync($"Installed binary: {deployment.InstalledExecutablePath}", cancellationToken).ConfigureAwait(false);
        await output.WriteSuccessAsync($"Installed wrapper: {deployment.WrapperPath}", cancellationToken).ConfigureAwait(false);
        await output.WriteSuccessAsync($"Installed docker proxy: {deployment.DockerProxyPath}", cancellationToken).ConfigureAwait(false);
        await output.WriteInfoAsync(
            $"Materialized assets (manifests={assets.ManifestFilesWritten}, templates={assets.TemplateFilesWritten}, examples={assets.ExampleFilesWritten}, default_config={assets.WroteDefaultConfig})",
            cancellationToken).ConfigureAwait(false);

        await shellIntegrationUpdater
            .EnsureShellIntegrationAsync(context.BinDir, context.HomeDirectory, context.Options.Yes, cancellationToken)
            .ConfigureAwait(false);

        if (context.Options.NoSetup)
        {
            await output.WriteInfoAsync("Skipping setup (--no-setup).", cancellationToken).ConfigureAwait(false);
            return 0;
        }

        return await setupRunner
            .RunSetupAsync(deployment.InstalledExecutablePath, context.Options, cancellationToken)
            .ConfigureAwait(false);
    }
}
