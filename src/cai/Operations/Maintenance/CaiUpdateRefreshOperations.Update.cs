namespace ContainAI.Cli.Host;

internal sealed partial class CaiUpdateRefreshOperations
{
    public async Task<int> RunUpdateAsync(
        bool dryRun,
        bool stopContainers,
        bool limaRecreate,
        bool showHelp,
        CancellationToken cancellationToken)
    {
        if (showHelp)
        {
            return await WriteUpdateUsageAsync().ConfigureAwait(false);
        }

        if (dryRun)
        {
            return await RunUpdateDryRunAsync(stopContainers, limaRecreate).ConfigureAwait(false);
        }

        if (limaRecreate && !OperatingSystem.IsMacOS())
        {
            await stderr.WriteLineAsync("--lima-recreate is only supported on macOS.").ConfigureAwait(false);
            return 1;
        }

        if (limaRecreate)
        {
            var recreateCode = await RecreateLimaVmAsync(cancellationToken).ConfigureAwait(false);
            if (recreateCode != 0)
            {
                return recreateCode;
            }
        }

        if (stopContainers)
        {
            await StopManagedContainersAsync(cancellationToken).ConfigureAwait(false);
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
