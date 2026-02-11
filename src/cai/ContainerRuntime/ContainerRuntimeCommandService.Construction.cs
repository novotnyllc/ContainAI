using ContainAI.Cli.Abstractions;
using ContainAI.Cli.Host.ContainerRuntime.Handlers;
using ContainAI.Cli.Host.ContainerRuntime.Infrastructure;
using ContainAI.Cli.Host.ContainerRuntime.Services;

namespace ContainAI.Cli.Host;

internal sealed partial class ContainerRuntimeCommandService
{
    public ContainerRuntimeCommandService(TextWriter standardOutput, TextWriter standardError)
        : this(standardOutput, standardError, new ManifestTomlParser(), new ContainerRuntimeOptionParser())
    {
    }

    internal ContainerRuntimeCommandService(
        TextWriter standardOutput,
        TextWriter standardError,
        IManifestTomlParser manifestTomlParser,
        IContainerRuntimeOptionParser optionParser)
    {
        ArgumentNullException.ThrowIfNull(standardOutput);
        ArgumentNullException.ThrowIfNull(standardError);

        this.optionParser = optionParser ?? throw new ArgumentNullException(nameof(optionParser));

        var executionContext = new ContainerRuntimeExecutionContext(standardOutput, standardError, manifestTomlParser);
        var envFileLoader = new ContainerRuntimeEnvironmentFileLoader(executionContext);
        var gitConfigService = new ContainerRuntimeGitConfigService(executionContext);
        var workspaceLinkService = new ContainerRuntimeWorkspaceLinkService(executionContext);
        var manifestBootstrapService = new ContainerRuntimeManifestBootstrapService(executionContext);
        var initWorkflow = new ContainerRuntimeInitializationWorkflow(
            executionContext,
            envFileLoader,
            gitConfigService,
            workspaceLinkService,
            manifestBootstrapService);

        initCommandHandler = new ContainerRuntimeInitCommandHandler(executionContext, initWorkflow);
        var linkSpecProcessor = new ContainerRuntimeLinkSpecProcessor(executionContext);
        linkRepairCommandHandler = new ContainerRuntimeLinkRepairCommandHandler(executionContext, linkSpecProcessor);
        watchLinksCommandHandler = new ContainerRuntimeWatchLinksCommandHandler(executionContext, linkRepairCommandHandler);
        devcontainerCommandHandler = new ContainerRuntimeDevcontainerCommandHandler(new DevcontainerFeatureRuntime(standardOutput, standardError));
    }

    internal ContainerRuntimeCommandService(
        IContainerRuntimeOptionParser optionParser,
        IContainerRuntimeInitCommandHandler initCommandHandler,
        IContainerRuntimeLinkRepairCommandHandler linkRepairCommandHandler,
        IContainerRuntimeWatchLinksCommandHandler watchLinksCommandHandler,
        IContainerRuntimeDevcontainerCommandHandler devcontainerCommandHandler)
    {
        this.optionParser = optionParser ?? throw new ArgumentNullException(nameof(optionParser));
        this.initCommandHandler = initCommandHandler ?? throw new ArgumentNullException(nameof(initCommandHandler));
        this.linkRepairCommandHandler = linkRepairCommandHandler ?? throw new ArgumentNullException(nameof(linkRepairCommandHandler));
        this.watchLinksCommandHandler = watchLinksCommandHandler ?? throw new ArgumentNullException(nameof(watchLinksCommandHandler));
        this.devcontainerCommandHandler = devcontainerCommandHandler ?? throw new ArgumentNullException(nameof(devcontainerCommandHandler));
    }
}
