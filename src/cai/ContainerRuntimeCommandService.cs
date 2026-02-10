using ContainAI.Cli.Abstractions;
using ContainAI.Cli.Host.ContainerRuntime.Handlers;
using ContainAI.Cli.Host.ContainerRuntime.Infrastructure;
using ContainAI.Cli.Host.ContainerRuntime.Services;

namespace ContainAI.Cli.Host;

internal sealed class ContainerRuntimeCommandService
{
    private readonly IContainerRuntimeOptionParser optionParser;
    private readonly IContainerRuntimeInitCommandHandler initCommandHandler;
    private readonly IContainerRuntimeLinkRepairCommandHandler linkRepairCommandHandler;
    private readonly IContainerRuntimeWatchLinksCommandHandler watchLinksCommandHandler;
    private readonly IContainerRuntimeDevcontainerCommandHandler devcontainerCommandHandler;

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

    public Task<int> RunSystemInitAsync(SystemInitCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return initCommandHandler.HandleAsync(optionParser.ParseInitCommandOptions(options), cancellationToken);
    }

    public Task<int> RunSystemLinkRepairAsync(SystemLinkRepairCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return linkRepairCommandHandler.HandleAsync(optionParser.ParseLinkRepairCommandOptions(options), cancellationToken);
    }

    public Task<int> RunSystemWatchLinksAsync(SystemWatchLinksCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return watchLinksCommandHandler.HandleAsync(optionParser.ParseWatchLinksCommandOptions(options), cancellationToken);
    }

    public Task<int> RunSystemDevcontainerInstallAsync(SystemDevcontainerInstallCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return devcontainerCommandHandler.InstallAsync(options, cancellationToken);
    }

    public Task<int> RunSystemDevcontainerInitAsync(CancellationToken cancellationToken)
        => devcontainerCommandHandler.InitAsync(cancellationToken);

    public Task<int> RunSystemDevcontainerStartAsync(CancellationToken cancellationToken)
        => devcontainerCommandHandler.StartAsync(cancellationToken);

    public Task<int> RunSystemDevcontainerVerifySysboxAsync(CancellationToken cancellationToken)
        => devcontainerCommandHandler.VerifySysboxAsync(cancellationToken);
}
