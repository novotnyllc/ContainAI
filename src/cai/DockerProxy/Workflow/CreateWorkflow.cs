namespace ContainAI.Cli.Host;

internal sealed class DockerProxyCreateWorkflow : IDockerProxyCreateWorkflow
{
    private readonly IDockerProxyArgumentParser argumentParser;
    private readonly IDevcontainerFeatureSettingsParser featureSettingsParser;
    private readonly IDockerProxyCommandExecutor commandExecutor;
    private readonly IContainAiSystemEnvironment environment;
    private readonly DockerProxyManagedCreateExecutor managedCreateExecutor;

    public DockerProxyCreateWorkflow(
        IDockerProxyArgumentParser argumentParser,
        IDevcontainerFeatureSettingsParser featureSettingsParser,
        IDockerProxyCommandExecutor commandExecutor,
        IDockerProxyPortAllocator portAllocator,
        IDockerProxyVolumeCredentialValidator volumeCredentialValidator,
        IDockerProxySshConfigUpdater sshConfigUpdater,
        IContainAiSystemEnvironment environment,
        IUtcClock clock)
    {
        this.argumentParser = argumentParser;
        this.featureSettingsParser = featureSettingsParser;
        this.commandExecutor = commandExecutor;
        this.environment = environment;
        managedCreateExecutor = new DockerProxyManagedCreateExecutor(
            argumentParser,
            commandExecutor,
            portAllocator,
            volumeCredentialValidator,
            sshConfigUpdater,
            clock);
    }

    public async Task<int> RunAsync(
        IReadOnlyList<string> dockerArgs,
        DockerProxyWrapperFlags wrapperFlags,
        string contextName,
        TextWriter stderr,
        CancellationToken cancellationToken)
    {
        var createParseResult = await DockerProxyCreateCommandRequestParser.ParseAsync(
            dockerArgs,
            contextName,
            argumentParser,
            featureSettingsParser,
            commandExecutor,
            environment,
            stderr,
            cancellationToken).ConfigureAwait(false);

        if (createParseResult.Status == DockerProxyCreateCommandParseStatus.Passthrough)
        {
            return await commandExecutor.RunInteractiveAsync(dockerArgs, stderr, cancellationToken).ConfigureAwait(false);
        }

        if (createParseResult.Status == DockerProxyCreateCommandParseStatus.SetupMissing)
        {
            return 1;
        }

        return await managedCreateExecutor.ExecuteAsync(
            dockerArgs,
            wrapperFlags,
            contextName,
            createParseResult.Request!,
            stderr,
            cancellationToken).ConfigureAwait(false);
    }
}
