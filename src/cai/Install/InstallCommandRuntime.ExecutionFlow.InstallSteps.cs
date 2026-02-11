using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed partial class InstallCommandExecution
{
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
