using ContainAI.Cli.Host.ContainerRuntime.Handlers;

namespace ContainAI.Cli.Host;

internal sealed partial class ContainerRuntimeCommandService
{
    private readonly IContainerRuntimeOptionParser optionParser;
    private readonly IContainerRuntimeInitCommandHandler initCommandHandler;
    private readonly IContainerRuntimeLinkRepairCommandHandler linkRepairCommandHandler;
    private readonly IContainerRuntimeWatchLinksCommandHandler watchLinksCommandHandler;
    private readonly IContainerRuntimeDevcontainerCommandHandler devcontainerCommandHandler;
}
