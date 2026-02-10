using ContainAI.Cli.Host.ContainerRuntime.Infrastructure;
using ContainAI.Cli.Host.ContainerRuntime.Models;
using ContainAI.Cli.Host;

namespace ContainAI.Cli.Host.ContainerRuntime.Handlers;

internal sealed partial class ContainerRuntimeWatchLinksCommandHandler : IContainerRuntimeWatchLinksCommandHandler
{
    private readonly IContainerRuntimeExecutionContext context;
    private readonly IContainerRuntimeLinkRepairCommandHandler linkRepairCommandHandler;

    public ContainerRuntimeWatchLinksCommandHandler(
        IContainerRuntimeExecutionContext context,
        IContainerRuntimeLinkRepairCommandHandler linkRepairCommandHandler)
    {
        this.context = context ?? throw new ArgumentNullException(nameof(context));
        this.linkRepairCommandHandler = linkRepairCommandHandler ?? throw new ArgumentNullException(nameof(linkRepairCommandHandler));
    }

    public async Task<int> HandleAsync(WatchLinksCommandParsing options, CancellationToken cancellationToken)
    {
        if (!await ValidateOptionsAsync(options).ConfigureAwait(false))
        {
            return 1;
        }

        await LogWatcherStartupAsync(options).ConfigureAwait(false);
        return await RunWatchLoopAsync(options, cancellationToken).ConfigureAwait(false);
    }
}
