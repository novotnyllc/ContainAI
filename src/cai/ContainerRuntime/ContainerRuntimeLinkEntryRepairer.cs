using ContainAI.Cli.Host.ContainerRuntime.Infrastructure;
using ContainAI.Cli.Host.ContainerRuntime.Models;

namespace ContainAI.Cli.Host.ContainerRuntime.Handlers;

internal sealed class ContainerRuntimeLinkEntryRepairer : IContainerRuntimeLinkEntryRepairer
{
    private readonly IContainerRuntimeLinkPathPreparationService linkPathPreparationService;
    private readonly IContainerRuntimeLinkCreationService linkCreationService;

    public ContainerRuntimeLinkEntryRepairer(IContainerRuntimeExecutionContext context)
        : this(
            new ContainerRuntimeLinkPathPreparationService(context ?? throw new ArgumentNullException(nameof(context))),
            new ContainerRuntimeLinkCreationService(context))
    {
    }

    internal ContainerRuntimeLinkEntryRepairer(
        IContainerRuntimeLinkPathPreparationService linkPathPreparationService,
        IContainerRuntimeLinkCreationService linkCreationService)
    {
        this.linkPathPreparationService = linkPathPreparationService ?? throw new ArgumentNullException(nameof(linkPathPreparationService));
        this.linkCreationService = linkCreationService ?? throw new ArgumentNullException(nameof(linkCreationService));
    }

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

        var canContinue = await linkPathPreparationService
            .PrepareAsync(linkPath, removeFirst, mode, quiet, stats)
            .ConfigureAwait(false);
        if (!canContinue)
        {
            return;
        }

        await linkCreationService
            .CreateAsync(linkPath, targetPath, mode, quiet, stats)
            .ConfigureAwait(false);
    }
}
