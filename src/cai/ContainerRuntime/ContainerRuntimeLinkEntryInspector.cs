using ContainAI.Cli.Host.ContainerRuntime.Infrastructure;
using ContainAI.Cli.Host.ContainerRuntime.Inspection;
using ContainAI.Cli.Host.ContainerRuntime.Models;

namespace ContainAI.Cli.Host.ContainerRuntime.Handlers;

internal sealed class ContainerRuntimeLinkEntryInspector : IContainerRuntimeLinkEntryInspector
{
    private readonly IContainerRuntimeExecutionContext context;
    private readonly ContainerRuntimeLinkEntryStateEvaluator stateEvaluator;

    public ContainerRuntimeLinkEntryInspector(IContainerRuntimeExecutionContext context)
    {
        this.context = context ?? throw new ArgumentNullException(nameof(context));
        stateEvaluator = new ContainerRuntimeLinkEntryStateEvaluator(this.context);
    }

    public async Task<ContainerRuntimeLinkInspectionResult> InspectAsync(
        string linkPath,
        string targetPath,
        bool removeFirst,
        bool quiet,
        LinkRepairStats stats)
    {
        var evaluation = await stateEvaluator
            .EvaluateAsync(linkPath, targetPath, removeFirst)
            .ConfigureAwait(false);

        switch (evaluation.State)
        {
            case ContainerRuntimeLinkInspectionState.Ok:
                stats.Ok++;
                return new ContainerRuntimeLinkInspectionResult(linkPath, targetPath, removeFirst, RequiresRepair: false);

            case ContainerRuntimeLinkInspectionState.BrokenDanglingSymlink:
                stats.Broken++;
                await context.LogInfoAsync(quiet, $"[BROKEN] {linkPath} -> {targetPath} (dangling symlink)").ConfigureAwait(false);
                break;

            case ContainerRuntimeLinkInspectionState.BrokenWrongTargetSymlink:
                stats.Broken++;
                await context.LogInfoAsync(quiet, $"[WRONG_TARGET] {linkPath} -> {evaluation.CurrentTarget} (expected: {targetPath})").ConfigureAwait(false);
                break;

            case ContainerRuntimeLinkInspectionState.BrokenDirectoryReplaceable:
                stats.Broken++;
                await context.LogInfoAsync(quiet, $"[EXISTS_DIR] {linkPath} is a directory (will remove with R flag)").ConfigureAwait(false);
                break;

            case ContainerRuntimeLinkInspectionState.DirectoryConflict:
                stats.Errors++;
                await context.StandardError.WriteLineAsync($"[CONFLICT] {linkPath} exists as directory (no R flag - cannot fix)").ConfigureAwait(false);
                return new ContainerRuntimeLinkInspectionResult(linkPath, targetPath, removeFirst, RequiresRepair: false);

            case ContainerRuntimeLinkInspectionState.BrokenFileReplaceable:
                stats.Broken++;
                await context.LogInfoAsync(quiet, $"[EXISTS_FILE] {linkPath} is a regular file (will replace)").ConfigureAwait(false);
                break;

            case ContainerRuntimeLinkInspectionState.Missing:
                stats.Missing++;
                await context.LogInfoAsync(quiet, $"[MISSING] {linkPath} -> {targetPath}").ConfigureAwait(false);
                break;
        }

        return new ContainerRuntimeLinkInspectionResult(linkPath, targetPath, removeFirst, RequiresRepair: true);
    }
}
