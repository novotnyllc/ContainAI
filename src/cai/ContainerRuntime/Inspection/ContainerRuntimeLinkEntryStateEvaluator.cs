using ContainAI.Cli.Host.ContainerRuntime.Infrastructure;

namespace ContainAI.Cli.Host.ContainerRuntime.Inspection;

internal sealed class ContainerRuntimeLinkEntryStateEvaluator
{
    private readonly IContainerRuntimeExecutionContext context;

    public ContainerRuntimeLinkEntryStateEvaluator(IContainerRuntimeExecutionContext context)
        => this.context = context ?? throw new ArgumentNullException(nameof(context));

    public async Task<ContainerRuntimeLinkEntryStateEvaluation> EvaluateAsync(
        string linkPath,
        string targetPath,
        bool removeFirst)
    {
        var isSymlink = await context.IsSymlinkAsync(linkPath).ConfigureAwait(false);
        if (isSymlink)
        {
            var currentTarget = await context.ReadLinkTargetAsync(linkPath).ConfigureAwait(false);
            if (string.Equals(currentTarget, targetPath, StringComparison.Ordinal))
            {
                if (!File.Exists(linkPath) && !Directory.Exists(linkPath))
                {
                    return new ContainerRuntimeLinkEntryStateEvaluation(
                        ContainerRuntimeLinkInspectionState.BrokenDanglingSymlink,
                        CurrentTarget: null);
                }

                return new ContainerRuntimeLinkEntryStateEvaluation(
                    ContainerRuntimeLinkInspectionState.Ok,
                    CurrentTarget: null);
            }

            return new ContainerRuntimeLinkEntryStateEvaluation(
                ContainerRuntimeLinkInspectionState.BrokenWrongTargetSymlink,
                CurrentTarget: currentTarget);
        }

        if (Directory.Exists(linkPath))
        {
            return removeFirst
                ? new ContainerRuntimeLinkEntryStateEvaluation(
                    ContainerRuntimeLinkInspectionState.BrokenDirectoryReplaceable,
                    CurrentTarget: null)
                : new ContainerRuntimeLinkEntryStateEvaluation(
                    ContainerRuntimeLinkInspectionState.DirectoryConflict,
                    CurrentTarget: null);
        }

        if (File.Exists(linkPath))
        {
            return new ContainerRuntimeLinkEntryStateEvaluation(
                ContainerRuntimeLinkInspectionState.BrokenFileReplaceable,
                CurrentTarget: null);
        }

        return new ContainerRuntimeLinkEntryStateEvaluation(
            ContainerRuntimeLinkInspectionState.Missing,
            CurrentTarget: null);
    }
}
