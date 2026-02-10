namespace ContainAI.Cli.Host;

internal sealed partial class ContainAiDockerProxyService : IContainAiDockerProxyService
{
    private readonly ContainAiDockerProxyOptions options;
    private readonly IDockerProxyArgumentParser argumentParser;
    private readonly IDevcontainerFeatureSettingsParser featureSettingsParser;
    private readonly IDockerProxyCommandExecutor commandExecutor;
    private readonly IDockerProxyContextSelector contextSelector;
    private readonly IDockerProxyPortAllocator portAllocator;
    private readonly IDockerProxyVolumeCredentialValidator volumeCredentialValidator;
    private readonly IDockerProxySshConfigUpdater sshConfigUpdater;
    private readonly IContainAiSystemEnvironment environment;
    private readonly IUtcClock clock;

    public ContainAiDockerProxyService(
        ContainAiDockerProxyOptions options,
        IDockerProxyArgumentParser argumentParser,
        IDevcontainerFeatureSettingsParser featureSettingsParser,
        IDockerProxyCommandExecutor commandExecutor,
        IDockerProxyContextSelector contextSelector,
        IDockerProxyPortAllocator portAllocator,
        IDockerProxyVolumeCredentialValidator volumeCredentialValidator,
        IDockerProxySshConfigUpdater sshConfigUpdater,
        IContainAiSystemEnvironment environment,
        IUtcClock clock)
    {
        this.options = options;
        this.argumentParser = argumentParser;
        this.featureSettingsParser = featureSettingsParser;
        this.commandExecutor = commandExecutor;
        this.contextSelector = contextSelector;
        this.portAllocator = portAllocator;
        this.volumeCredentialValidator = volumeCredentialValidator;
        this.sshConfigUpdater = sshConfigUpdater;
        this.environment = environment;
        this.clock = clock;
    }

    public async Task<int> RunAsync(IReadOnlyList<string> args, TextWriter stdout, TextWriter stderr, CancellationToken cancellationToken)
    {
        _ = stdout;

        var contextName = ResolveContextName();
        var wrapperFlags = argumentParser.ParseWrapperFlags(args);
        var dockerArgs = wrapperFlags.DockerArgs;

        if (!argumentParser.IsContainerCreateCommand(dockerArgs))
        {
            return await RunNonCreateAsync(dockerArgs, contextName, stderr, cancellationToken).ConfigureAwait(false);
        }

        return await RunCreateAsync(dockerArgs, wrapperFlags, contextName, stderr, cancellationToken).ConfigureAwait(false);
    }
}
