using ContainAI.Cli.Host.ContainerRuntime.Infrastructure;
using ContainAI.Cli.Host.ContainerRuntime.Models;

namespace ContainAI.Cli.Host.ContainerRuntime.Handlers;

internal interface IContainerRuntimeLinkEntryRepairer
{
    Task RepairAsync(
        string linkPath,
        string targetPath,
        bool removeFirst,
        LinkRepairMode mode,
        bool quiet,
        LinkRepairStats stats);
}

internal sealed class ContainerRuntimeLinkEntryRepairer : IContainerRuntimeLinkEntryRepairer
{
    private readonly IContainerRuntimeExecutionContext context;

    public ContainerRuntimeLinkEntryRepairer(IContainerRuntimeExecutionContext context)
        => this.context = context ?? throw new ArgumentNullException(nameof(context));

    public async Task RepairAsync(
        string linkPath,
        string targetPath,
        bool removeFirst,
        LinkRepairMode mode,
        bool quiet,
        LinkRepairStats stats)
    {
        if (mode == LinkRepairMode.Check)
        {
            return;
        }

        await EnsureParentDirectoryAsync(linkPath, mode, quiet).ConfigureAwait(false);
        var canContinue = await RemoveExistingPathIfNeededAsync(linkPath, removeFirst, mode, quiet, stats).ConfigureAwait(false);
        if (!canContinue)
        {
            return;
        }

        await CreateSymlinkAsync(linkPath, targetPath, mode, quiet, stats).ConfigureAwait(false);
    }

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
