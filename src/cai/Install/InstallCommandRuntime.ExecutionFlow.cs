using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal interface IInstallCommandExecution
{
    Task<int> RunAsync(InstallCommandOptions options, CancellationToken cancellationToken);
}

internal sealed class InstallCommandExecution : IInstallCommandExecution
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

    public async Task<int> RunAsync(InstallCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);

        var installDir = pathResolver.ResolveInstallDirectory(options.InstallDir);
        var binDir = pathResolver.ResolveBinDirectory(options.BinDir);
        var homeDirectory = pathResolver.ResolveHomeDirectory();

        await output.WriteInfoAsync("ContainAI installer starting", cancellationToken).ConfigureAwait(false);
        await output.WriteInfoAsync($"Install directory: {installDir}", cancellationToken).ConfigureAwait(false);
        await output.WriteInfoAsync($"Binary directory: {binDir}", cancellationToken).ConfigureAwait(false);

        if (!string.IsNullOrWhiteSpace(options.Channel))
        {
            await output.WriteInfoAsync($"Channel: {options.Channel}", cancellationToken).ConfigureAwait(false);
        }

        var sourceExecutablePath = pathResolver.ResolveCurrentExecutablePath();
        if (sourceExecutablePath is null)
        {
            await output.WriteErrorAsync("Unable to resolve the current cai executable path.", cancellationToken).ConfigureAwait(false);
            return 1;
        }

        try
        {
            return await ExecuteInstallFlowAsync(
                options,
                sourceExecutablePath,
                installDir,
                binDir,
                homeDirectory,
                cancellationToken).ConfigureAwait(false);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (IOException ex)
        {
            return await WriteErrorAndReturnAsync(ex.Message, cancellationToken).ConfigureAwait(false);
        }
        catch (UnauthorizedAccessException ex)
        {
            return await WriteErrorAndReturnAsync(ex.Message, cancellationToken).ConfigureAwait(false);
        }
        catch (ArgumentException ex)
        {
            return await WriteErrorAndReturnAsync(ex.Message, cancellationToken).ConfigureAwait(false);
        }
        catch (NotSupportedException ex)
        {
            return await WriteErrorAndReturnAsync(ex.Message, cancellationToken).ConfigureAwait(false);
        }
        catch (InvalidOperationException ex)
        {
            return await WriteErrorAndReturnAsync(ex.Message, cancellationToken).ConfigureAwait(false);
        }
    }

    private async Task<int> ExecuteInstallFlowAsync(
        InstallCommandOptions options,
        string sourceExecutablePath,
        string installDir,
        string binDir,
        string homeDirectory,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        var deployment = deploymentService.Deploy(sourceExecutablePath, installDir, binDir);
        var assets = assetMaterializer.Materialize(installDir, homeDirectory);

        await output.WriteSuccessAsync($"Installed binary: {deployment.InstalledExecutablePath}", cancellationToken).ConfigureAwait(false);
        await output.WriteSuccessAsync($"Installed wrapper: {deployment.WrapperPath}", cancellationToken).ConfigureAwait(false);
        await output.WriteSuccessAsync($"Installed docker proxy: {deployment.DockerProxyPath}", cancellationToken).ConfigureAwait(false);
        await output.WriteInfoAsync(
            $"Materialized assets (manifests={assets.ManifestFilesWritten}, templates={assets.TemplateFilesWritten}, examples={assets.ExampleFilesWritten}, default_config={assets.WroteDefaultConfig})",
            cancellationToken).ConfigureAwait(false);

        await shellIntegrationUpdater
            .EnsureShellIntegrationAsync(binDir, homeDirectory, options.Yes, cancellationToken)
            .ConfigureAwait(false);

        if (options.NoSetup)
        {
            await output.WriteInfoAsync("Skipping setup (--no-setup).", cancellationToken).ConfigureAwait(false);
            return 0;
        }

        return await setupRunner.RunSetupAsync(deployment.InstalledExecutablePath, options, cancellationToken).ConfigureAwait(false);
    }

    private async Task<int> WriteErrorAndReturnAsync(string message, CancellationToken cancellationToken)
    {
        await output.WriteErrorAsync(message, cancellationToken).ConfigureAwait(false);
        return 1;
    }
}
