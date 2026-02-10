using ContainAI.Cli.Host.ContainerRuntime.Infrastructure;
using ContainAI.Cli.Host.ContainerRuntime.Models;

namespace ContainAI.Cli.Host.ContainerRuntime.Handlers;

internal interface IContainerRuntimeLinkEntryInspector
{
    Task<ContainerRuntimeLinkInspectionResult> InspectAsync(
        string linkPath,
        string targetPath,
        bool removeFirst,
        bool quiet,
        LinkRepairStats stats);
}

internal sealed class ContainerRuntimeLinkEntryInspector : IContainerRuntimeLinkEntryInspector
{
    private readonly IContainerRuntimeExecutionContext context;

    public ContainerRuntimeLinkEntryInspector(IContainerRuntimeExecutionContext context)
        => this.context = context ?? throw new ArgumentNullException(nameof(context));

    public async Task<ContainerRuntimeLinkInspectionResult> InspectAsync(
        string linkPath,
        string targetPath,
        bool removeFirst,
        bool quiet,
        LinkRepairStats stats)
    {
        var isSymlink = await context.IsSymlinkAsync(linkPath).ConfigureAwait(false);
        if (isSymlink)
        {
            var currentTarget = await context.ReadLinkTargetAsync(linkPath).ConfigureAwait(false);
            if (string.Equals(currentTarget, targetPath, StringComparison.Ordinal))
            {
                if (!File.Exists(linkPath) && !Directory.Exists(linkPath))
                {
                    stats.Broken++;
                    await context.LogInfoAsync(quiet, $"[BROKEN] {linkPath} -> {targetPath} (dangling symlink)").ConfigureAwait(false);
                }
                else
                {
                    stats.Ok++;
                    return new ContainerRuntimeLinkInspectionResult(linkPath, targetPath, removeFirst, RequiresRepair: false);
                }
            }
            else
            {
                stats.Broken++;
                await context.LogInfoAsync(quiet, $"[WRONG_TARGET] {linkPath} -> {currentTarget} (expected: {targetPath})").ConfigureAwait(false);
            }
        }
        else if (Directory.Exists(linkPath))
        {
            if (removeFirst)
            {
                stats.Broken++;
                await context.LogInfoAsync(quiet, $"[EXISTS_DIR] {linkPath} is a directory (will remove with R flag)").ConfigureAwait(false);
            }
            else
            {
                stats.Errors++;
                await context.StandardError.WriteLineAsync($"[CONFLICT] {linkPath} exists as directory (no R flag - cannot fix)").ConfigureAwait(false);
                return new ContainerRuntimeLinkInspectionResult(linkPath, targetPath, removeFirst, RequiresRepair: false);
            }
        }
        else if (File.Exists(linkPath))
        {
            stats.Broken++;
            await context.LogInfoAsync(quiet, $"[EXISTS_FILE] {linkPath} is a regular file (will replace)").ConfigureAwait(false);
        }
        else
        {
            stats.Missing++;
            await context.LogInfoAsync(quiet, $"[MISSING] {linkPath} -> {targetPath}").ConfigureAwait(false);
        }

        return new ContainerRuntimeLinkInspectionResult(linkPath, targetPath, removeFirst, RequiresRepair: true);
    }
}
