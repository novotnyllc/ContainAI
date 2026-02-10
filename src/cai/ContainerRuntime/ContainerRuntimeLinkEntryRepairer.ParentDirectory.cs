using ContainAI.Cli.Host.ContainerRuntime.Models;

namespace ContainAI.Cli.Host.ContainerRuntime.Handlers;

internal sealed partial class ContainerRuntimeLinkEntryRepairer
{
    private async Task EnsureParentDirectoryAsync(string linkPath, LinkRepairMode mode, bool quiet)
    {
        var parent = Path.GetDirectoryName(linkPath);
        if (string.IsNullOrWhiteSpace(parent) || Directory.Exists(parent))
        {
            return;
        }

        if (mode == LinkRepairMode.DryRun)
        {
            await context.LogInfoAsync(quiet, $"[WOULD] Create parent directory: {parent}").ConfigureAwait(false);
        }
        else
        {
            Directory.CreateDirectory(parent);
        }
    }
}
