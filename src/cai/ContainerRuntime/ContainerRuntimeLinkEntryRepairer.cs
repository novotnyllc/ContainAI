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

internal sealed partial class ContainerRuntimeLinkEntryRepairer : IContainerRuntimeLinkEntryRepairer
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
}
