namespace ContainAI.Cli.Host;

internal sealed class CaiUninstallOperations
{
    private readonly TextWriter stdout;
    private readonly ICaiUninstallShellIntegrationCleaner shellIntegrationCleaner;
    private readonly ICaiUninstallDockerContextCleaner dockerContextCleaner;
    private readonly ICaiUninstallContainerAndVolumeCleaner containerAndVolumeCleaner;

    public CaiUninstallOperations(TextWriter standardOutput, TextWriter standardError)
        : this(
            standardOutput,
            new CaiUninstallShellIntegrationCleaner(standardOutput),
            new CaiUninstallDockerContextCleaner(standardOutput),
            new CaiUninstallContainerAndVolumeCleaner(standardOutput, standardError))
    {
    }

    internal CaiUninstallOperations(
        TextWriter standardOutput,
        ICaiUninstallShellIntegrationCleaner caiUninstallShellIntegrationCleaner,
        ICaiUninstallDockerContextCleaner caiUninstallDockerContextCleaner,
        ICaiUninstallContainerAndVolumeCleaner caiUninstallContainerAndVolumeCleaner)
    {
        stdout = standardOutput ?? throw new ArgumentNullException(nameof(standardOutput));
        shellIntegrationCleaner = caiUninstallShellIntegrationCleaner ?? throw new ArgumentNullException(nameof(caiUninstallShellIntegrationCleaner));
        dockerContextCleaner = caiUninstallDockerContextCleaner ?? throw new ArgumentNullException(nameof(caiUninstallDockerContextCleaner));
        containerAndVolumeCleaner = caiUninstallContainerAndVolumeCleaner ?? throw new ArgumentNullException(nameof(caiUninstallContainerAndVolumeCleaner));
    }

    public async Task<int> RunUninstallAsync(
        bool dryRun,
        bool removeContainers,
        bool removeVolumes,
        bool showHelp,
        CancellationToken cancellationToken)
    {
        if (showHelp)
        {
            await stdout.WriteLineAsync("Usage: cai uninstall [--dry-run] [--containers] [--volumes] [--force]").ConfigureAwait(false);
            return 0;
        }

        await shellIntegrationCleaner.CleanAsync(dryRun, cancellationToken).ConfigureAwait(false);
        await dockerContextCleaner.CleanAsync(dryRun, cancellationToken).ConfigureAwait(false);

        if (!removeContainers)
        {
            await stdout.WriteLineAsync("Uninstall complete (contexts cleaned). Use --containers/--volumes for full cleanup.").ConfigureAwait(false);
            return 0;
        }

        var removeResult = await containerAndVolumeCleaner
            .RemoveManagedContainersAndCollectVolumesAsync(dryRun, removeVolumes, cancellationToken)
            .ConfigureAwait(false);

        if (removeResult.ExitCode != 0)
        {
            return 1;
        }

        await containerAndVolumeCleaner
            .RemoveVolumesAsync(removeResult.VolumeNames, dryRun, cancellationToken)
            .ConfigureAwait(false);

        await stdout.WriteLineAsync("Uninstall complete.").ConfigureAwait(false);
        return 0;
    }
}
