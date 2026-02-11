namespace ContainAI.Cli.Host;

internal interface ICaiUpdateOperations
{
    Task<int> RunUpdateAsync(
        bool dryRun,
        bool stopContainers,
        bool limaRecreate,
        bool showHelp,
        CancellationToken cancellationToken);
}

internal sealed class CaiUpdateOperations : ICaiUpdateOperations
{
    private readonly TextWriter stdout;
    private readonly TextWriter stderr;
    private readonly ICaiRefreshOperations refreshOperations;
    private readonly ICaiManagedContainerStopper managedContainerStopper;
    private readonly ICaiLimaVmRecreator limaVmRecreator;
    private readonly Func<bool, bool, bool, CancellationToken, Task<int>> runDoctorAsync;

    public CaiUpdateOperations(
        TextWriter standardOutput,
        TextWriter standardError,
        ICaiRefreshOperations caiRefreshOperations,
        ICaiManagedContainerStopper caiManagedContainerStopper,
        ICaiLimaVmRecreator caiLimaVmRecreator,
        Func<bool, bool, bool, CancellationToken, Task<int>> runDoctorAsync)
    {
        stdout = standardOutput ?? throw new ArgumentNullException(nameof(standardOutput));
        stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));
        refreshOperations = caiRefreshOperations ?? throw new ArgumentNullException(nameof(caiRefreshOperations));
        managedContainerStopper = caiManagedContainerStopper ?? throw new ArgumentNullException(nameof(caiManagedContainerStopper));
        limaVmRecreator = caiLimaVmRecreator ?? throw new ArgumentNullException(nameof(caiLimaVmRecreator));
        this.runDoctorAsync = runDoctorAsync ?? throw new ArgumentNullException(nameof(runDoctorAsync));
    }

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
            var recreateCode = await limaVmRecreator.RecreateAsync(cancellationToken).ConfigureAwait(false);
            if (recreateCode != 0)
            {
                return recreateCode;
            }
        }

        if (stopContainers)
        {
            await managedContainerStopper.StopAsync(cancellationToken).ConfigureAwait(false);
        }

        var refreshCode = await refreshOperations.RunRefreshAsync(rebuild: true, showHelp: false, cancellationToken).ConfigureAwait(false);
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

    private async Task<int> WriteUpdateUsageAsync()
    {
        await stdout.WriteLineAsync("Usage: cai update [--dry-run] [--stop-containers] [--force] [--lima-recreate]").ConfigureAwait(false);
        return 0;
    }

    private async Task<int> RunUpdateDryRunAsync(bool stopContainers, bool limaRecreate)
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
}
