using ContainAI.Cli.Host.ContainerRuntime.Models;

namespace ContainAI.Cli.Host.ContainerRuntime.Handlers;

internal sealed partial class ContainerRuntimeLinkEntryRepairer
{
    private async Task<bool> RemoveExistingPathIfNeededAsync(
        string linkPath,
        bool removeFirst,
        LinkRepairMode mode,
        bool quiet,
        LinkRepairStats stats)
    {
        if (Directory.Exists(linkPath) && !await context.IsSymlinkAsync(linkPath).ConfigureAwait(false))
        {
            if (!removeFirst)
            {
                stats.Errors++;
                await context.StandardError.WriteLineAsync($"ERROR: Cannot fix - directory exists without R flag: {linkPath}").ConfigureAwait(false);
                return false;
            }

            if (mode == LinkRepairMode.DryRun)
            {
                await context.LogInfoAsync(quiet, $"[WOULD] Remove directory: {linkPath}").ConfigureAwait(false);
            }
            else
            {
                Directory.Delete(linkPath, recursive: true);
            }

            return true;
        }

        if (File.Exists(linkPath) || await context.IsSymlinkAsync(linkPath).ConfigureAwait(false))
        {
            if (mode == LinkRepairMode.DryRun)
            {
                await context.LogInfoAsync(quiet, $"[WOULD] Replace path: {linkPath}").ConfigureAwait(false);
            }
            else
            {
                File.Delete(linkPath);
            }
        }

        return true;
    }
}
