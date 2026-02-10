namespace ContainAI.Cli.Host;

internal sealed partial class CaiUninstallOperations : CaiRuntimeSupport
{
    public CaiUninstallOperations(TextWriter standardOutput, TextWriter standardError)
        : base(standardOutput, standardError)
    {
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

        await RemoveShellIntegrationAsync(dryRun, cancellationToken).ConfigureAwait(false);

        await RemoveDockerContextsAsync(dryRun, cancellationToken).ConfigureAwait(false);

        if (!removeContainers)
        {
            await stdout.WriteLineAsync("Uninstall complete (contexts cleaned). Use --containers/--volumes for full cleanup.").ConfigureAwait(false);
            return 0;
        }

        var removeResult = await RemoveManagedContainersAndCollectVolumesAsync(dryRun, removeVolumes, cancellationToken).ConfigureAwait(false);
        if (removeResult.ExitCode != 0)
        {
            return 1;
        }

        await RemoveVolumesAsync(removeResult.VolumeNames, dryRun, cancellationToken).ConfigureAwait(false);

        await stdout.WriteLineAsync("Uninstall complete.").ConfigureAwait(false);
        return 0;
    }
}
