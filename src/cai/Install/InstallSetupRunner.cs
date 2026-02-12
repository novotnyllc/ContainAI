using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed class InstallSetupRunner : IInstallSetupRunner
{
    private readonly IInstallCommandOutput output;

    public InstallSetupRunner(IInstallCommandOutput output)
        => this.output = output ?? throw new ArgumentNullException(nameof(output));

    public async Task<int> RunSetupAsync(
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
            await output.WriteWarningAsync("Dry-run setup failed; continuing with setup.", cancellationToken).ConfigureAwait(false);
            if (options.Verbose && !string.IsNullOrWhiteSpace(dryRun.StandardError))
            {
                await output.WriteRawErrorAsync(dryRun.StandardError.Trim(), cancellationToken).ConfigureAwait(false);
            }
        }

        var setupArgs = options.Verbose
            ? new[] { "setup", "--verbose" }
            : new[] { "setup" };
        await output.WriteInfoAsync("Running post-install setup.", cancellationToken).ConfigureAwait(false);
        var setupExitCode = await CliWrapProcessRunner.RunInteractiveAsync(
            installedBinary,
            setupArgs,
            cancellationToken,
            environment: environment).ConfigureAwait(false);
        if (setupExitCode == 0)
        {
            await output.WriteSuccessAsync("Post-install setup completed.", cancellationToken).ConfigureAwait(false);
            return 0;
        }

        await output.WriteWarningAsync($"Setup exited with code {setupExitCode}. Run `cai setup` to retry.", cancellationToken).ConfigureAwait(false);
        return setupExitCode;
    }
}
