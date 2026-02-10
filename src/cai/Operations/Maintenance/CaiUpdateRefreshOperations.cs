namespace ContainAI.Cli.Host;

internal sealed partial class CaiUpdateRefreshOperations : CaiRuntimeSupport
{
    private readonly Func<bool, bool, bool, CancellationToken, Task<int>> runDoctorAsync;

    public CaiUpdateRefreshOperations(
        TextWriter standardOutput,
        TextWriter standardError,
        Func<bool, bool, bool, CancellationToken, Task<int>> runDoctorAsync)
        : base(standardOutput, standardError)
        => this.runDoctorAsync = runDoctorAsync ?? throw new ArgumentNullException(nameof(runDoctorAsync));

    public async Task<int> RunUpdateAsync(
        bool dryRun,
        bool stopContainers,
        bool limaRecreate,
        bool showHelp,
        CancellationToken cancellationToken)
    {
        if (showHelp)
        {
            await stdout.WriteLineAsync("Usage: cai update [--dry-run] [--stop-containers] [--force] [--lima-recreate]").ConfigureAwait(false);
            return 0;
        }

        if (dryRun)
        {
            await stdout.WriteLineAsync("Would pull latest base image for configured channel.").ConfigureAwait(false);
            if (stopContainers)
            {
                await stdout.WriteLineAsync("Would stop running ContainAI containers before update.").ConfigureAwait(false);
            }

            if (limaRecreate)
            {
                await stdout.WriteLineAsync("Would recreate Lima VM 'containai'.").ConfigureAwait(false);
            }

            await stdout.WriteLineAsync("Would refresh templates and verify installation.").ConfigureAwait(false);
            return 0;
        }

        if (limaRecreate && !OperatingSystem.IsMacOS())
        {
            await stderr.WriteLineAsync("--lima-recreate is only supported on macOS.").ConfigureAwait(false);
            return 1;
        }

        if (limaRecreate)
        {
            await stdout.WriteLineAsync("Recreating Lima VM 'containai'...").ConfigureAwait(false);
            await RunProcessCaptureAsync("limactl", ["delete", "containai", "--force"], cancellationToken).ConfigureAwait(false);
            var start = await RunProcessCaptureAsync("limactl", ["start", "containai"], cancellationToken).ConfigureAwait(false);
            if (start.ExitCode != 0)
            {
                await stderr.WriteLineAsync(start.StandardError.Trim()).ConfigureAwait(false);
                return 1;
            }
        }

        if (stopContainers)
        {
            var stopResult = await DockerCaptureAsync(
                ["ps", "-q", "--filter", "label=containai.managed=true"],
                cancellationToken).ConfigureAwait(false);

            if (stopResult.ExitCode == 0)
            {
                foreach (var containerId in stopResult.StandardOutput.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
                {
                    await DockerCaptureAsync(["stop", containerId], cancellationToken).ConfigureAwait(false);
                }
            }
        }

        var refreshCode = await RunRefreshAsync(rebuild: true, showHelp: false, cancellationToken).ConfigureAwait(false);
        if (refreshCode != 0)
        {
            return refreshCode;
        }

        var doctorCode = await runDoctorAsync(false, false, false, cancellationToken).ConfigureAwait(false);
        if (doctorCode != 0)
        {
            await stderr.WriteLineAsync("Update completed with validation warnings. Run `cai doctor` for details.").ConfigureAwait(false);
            return 1;
        }

        await stdout.WriteLineAsync("Update complete.").ConfigureAwait(false);
        return 0;
    }
}
