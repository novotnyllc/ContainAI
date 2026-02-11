namespace ContainAI.Cli.Host;

internal interface ICaiUpdateExecutionOrchestrator
{
    Task<int> ExecuteUpdateAsync(bool stopContainers, bool limaRecreate, CancellationToken cancellationToken);
}

internal sealed class CaiUpdateExecutionOrchestrator : ICaiUpdateExecutionOrchestrator
{
    private readonly TextWriter stdout;
    private readonly TextWriter stderr;
    private readonly ICaiRefreshOperations refreshOperations;
    private readonly ICaiManagedContainerStopper managedContainerStopper;
    private readonly ICaiLimaVmRecreator limaVmRecreator;
    private readonly Func<bool, bool, bool, CancellationToken, Task<int>> runDoctorAsync;

    public CaiUpdateExecutionOrchestrator(
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

    public async Task<int> ExecuteUpdateAsync(bool stopContainers, bool limaRecreate, CancellationToken cancellationToken)
    {
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
}
