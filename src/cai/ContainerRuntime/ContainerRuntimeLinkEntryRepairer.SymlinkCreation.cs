using ContainAI.Cli.Host.ContainerRuntime.Models;

namespace ContainAI.Cli.Host.ContainerRuntime.Handlers;

internal sealed partial class ContainerRuntimeLinkEntryRepairer
{
    private async Task CreateSymlinkAsync(
        string linkPath,
        string targetPath,
        LinkRepairMode mode,
        bool quiet,
        LinkRepairStats stats)
    {
        if (mode == LinkRepairMode.DryRun)
        {
            await context.LogInfoAsync(quiet, $"[WOULD] Create symlink: {linkPath} -> {targetPath}").ConfigureAwait(false);
            stats.Fixed++;
            return;
        }

        File.CreateSymbolicLink(linkPath, targetPath);
        await context.LogInfoAsync(quiet, $"[FIXED] {linkPath} -> {targetPath}").ConfigureAwait(false);
        stats.Fixed++;
    }
}
