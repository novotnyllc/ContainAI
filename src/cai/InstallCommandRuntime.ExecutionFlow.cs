using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed partial class InstallCommandRuntime
{
    public async Task<int> RunAsync(InstallCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);

        var installDir = ResolveInstallDirectory(options.InstallDir);
        var binDir = ResolveBinDirectory(options.BinDir);
        var homeDirectory = ResolveHomeDirectory();

        await WriteInfoAsync("ContainAI installer starting", cancellationToken).ConfigureAwait(false);
        await WriteInfoAsync($"Install directory: {installDir}", cancellationToken).ConfigureAwait(false);
        await WriteInfoAsync($"Binary directory: {binDir}", cancellationToken).ConfigureAwait(false);

        if (!string.IsNullOrWhiteSpace(options.Channel))
        {
            await WriteInfoAsync($"Channel: {options.Channel}", cancellationToken).ConfigureAwait(false);
        }

        var sourceExecutablePath = ResolveCurrentExecutablePath();
        if (sourceExecutablePath is null)
        {
            await WriteErrorAsync("Unable to resolve the current cai executable path.", cancellationToken).ConfigureAwait(false);
            return 1;
        }

        try
        {
            cancellationToken.ThrowIfCancellationRequested();

            var deployment = InstallDeploymentService.Deploy(sourceExecutablePath, installDir, binDir);
            var assets = InstallAssetMaterializer.Materialize(installDir, homeDirectory);

            await WriteSuccessAsync($"Installed binary: {deployment.InstalledExecutablePath}", cancellationToken).ConfigureAwait(false);
            await WriteSuccessAsync($"Installed wrapper: {deployment.WrapperPath}", cancellationToken).ConfigureAwait(false);
            await WriteSuccessAsync($"Installed docker proxy: {deployment.DockerProxyPath}", cancellationToken).ConfigureAwait(false);
            await WriteInfoAsync(
                $"Materialized assets (manifests={assets.ManifestFilesWritten}, templates={assets.TemplateFilesWritten}, examples={assets.ExampleFilesWritten}, default_config={assets.WroteDefaultConfig})",
                cancellationToken).ConfigureAwait(false);

            await EnsureShellIntegrationAsync(binDir, homeDirectory, options.Yes, cancellationToken).ConfigureAwait(false);

            if (options.NoSetup)
            {
                await WriteInfoAsync("Skipping setup (--no-setup).", cancellationToken).ConfigureAwait(false);
                return 0;
            }

            return await RunSetupAsync(deployment.InstalledExecutablePath, options, cancellationToken).ConfigureAwait(false);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (IOException ex)
        {
            await WriteErrorAsync(ex.Message, cancellationToken).ConfigureAwait(false);
            return 1;
        }
        catch (UnauthorizedAccessException ex)
        {
            await WriteErrorAsync(ex.Message, cancellationToken).ConfigureAwait(false);
            return 1;
        }
        catch (ArgumentException ex)
        {
            await WriteErrorAsync(ex.Message, cancellationToken).ConfigureAwait(false);
            return 1;
        }
        catch (NotSupportedException ex)
        {
            await WriteErrorAsync(ex.Message, cancellationToken).ConfigureAwait(false);
            return 1;
        }
        catch (InvalidOperationException ex)
        {
            await WriteErrorAsync(ex.Message, cancellationToken).ConfigureAwait(false);
            return 1;
        }
    }

    private async Task<int> RunSetupAsync(
        string installedBinary,
        InstallCommandOptions options,
        CancellationToken cancellationToken)
    {
        var environment = options.Yes
            ? new Dictionary<string, string?>(StringComparer.Ordinal) { ["CAI_YES"] = "1" }
            : null;

        var dryRunArgs = options.Verbose
            ? new[] { "setup", "--dry-run", "--verbose" }
            : new[] { "setup", "--dry-run" };
        var dryRun = await CliWrapProcessRunner.RunCaptureAsync(
            installedBinary,
            dryRunArgs,
            cancellationToken,
            environment: environment).ConfigureAwait(false);
        if (dryRun.ExitCode != 0)
        {
            await WriteWarningAsync("Dry-run setup failed; continuing with setup.", cancellationToken).ConfigureAwait(false);
            if (options.Verbose && !string.IsNullOrWhiteSpace(dryRun.StandardError))
            {
                await stderr.WriteLineAsync(dryRun.StandardError.Trim()).ConfigureAwait(false);
            }
        }

        var setupArgs = options.Verbose
            ? new[] { "setup", "--verbose" }
            : new[] { "setup" };
        await WriteInfoAsync("Running post-install setup.", cancellationToken).ConfigureAwait(false);
        var setupExitCode = await CliWrapProcessRunner.RunInteractiveAsync(
            installedBinary,
            setupArgs,
            cancellationToken,
            environment: environment).ConfigureAwait(false);
        if (setupExitCode == 0)
        {
            await WriteSuccessAsync("Post-install setup completed.", cancellationToken).ConfigureAwait(false);
            return 0;
        }

        await WriteWarningAsync($"Setup exited with code {setupExitCode}. Run `cai setup` to retry.", cancellationToken).ConfigureAwait(false);
        return setupExitCode;
    }

    private async Task EnsureShellIntegrationAsync(
        string binDir,
        string homeDirectory,
        bool autoUpdateShellConfig,
        CancellationToken cancellationToken)
    {
        if (!autoUpdateShellConfig)
        {
            await WriteWarningAsync(
                $"Shell integration not updated. Rerun with --yes to wire PATH/completions for `{binDir}`.",
                cancellationToken).ConfigureAwait(false);
            return;
        }

        var profileScriptUpdated = await ShellProfileIntegration
            .EnsureProfileScriptAsync(homeDirectory, binDir, cancellationToken)
            .ConfigureAwait(false);
        var shellProfilePath = ShellProfileIntegration.ResolvePreferredShellProfilePath(homeDirectory, Environment.GetEnvironmentVariable("SHELL"));
        var shellHookUpdated = await ShellProfileIntegration
            .EnsureHookInShellProfileAsync(shellProfilePath, cancellationToken)
            .ConfigureAwait(false);
        if (!profileScriptUpdated && !shellHookUpdated)
        {
            return;
        }

        await WriteInfoAsync($"Updated shell integration in {shellProfilePath}", cancellationToken).ConfigureAwait(false);
    }
}
