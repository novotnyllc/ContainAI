namespace ContainAI.Cli.Host;

internal sealed class ContainAiDockerProxyService : IContainAiDockerProxyService
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

    private string ResolveContextName()
    {
        var contextName = environment.GetEnvironmentVariable("CONTAINAI_DOCKER_CONTEXT");
        if (string.IsNullOrWhiteSpace(contextName))
        {
            contextName = options.DefaultContext;
        }

        return contextName;
    }

    private async Task<int> RunCreateAsync(
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

        var request = createParseResult.Request!;

        var sshPort = await portAllocator.AllocateSshPortAsync(
            request.LockPath,
            request.ContainAiConfigDir,
            contextName,
            request.Workspace.Name,
            request.Workspace.SanitizedName,
            cancellationToken).ConfigureAwait(false);

        var mountVolume = await volumeCredentialValidator.ValidateAsync(
            contextName,
            request.Settings.DataVolume,
            request.Settings.EnableCredentials,
            wrapperFlags.Quiet,
            stderr,
            cancellationToken).ConfigureAwait(false);

        var modifiedArgs = await DockerProxyCreateCommandOutputBuilder.BuildManagedCreateArgumentsAsync(
            dockerArgs,
            contextName,
            request.Workspace.Name,
            request.Settings,
            sshPort,
            mountVolume,
            wrapperFlags.Quiet,
            commandExecutor,
            clock,
            stderr,
            cancellationToken).ConfigureAwait(false);

        await sshConfigUpdater
            .UpdateAsync(request.Workspace.SanitizedName, sshPort, request.Settings.RemoteUser, stderr, cancellationToken)
            .ConfigureAwait(false);
        await DockerProxyCreateCommandOutputBuilder
            .WriteVerboseExecutionAsync(wrapperFlags.Verbose, wrapperFlags.Quiet, contextName, modifiedArgs, stderr)
            .ConfigureAwait(false);

        return await commandExecutor.RunInteractiveAsync(
            argumentParser.PrependContext(contextName, modifiedArgs),
            stderr,
            cancellationToken).ConfigureAwait(false);
    }

    private async Task<int> RunNonCreateAsync(
        IReadOnlyList<string> dockerArgs,
        string contextName,
        TextWriter stderr,
        CancellationToken cancellationToken)
    {
        var useContainAiContext = await contextSelector
            .ShouldUseContainAiContextAsync(dockerArgs, contextName, cancellationToken)
            .ConfigureAwait(false);

        return await commandExecutor.RunInteractiveAsync(
            useContainAiContext ? argumentParser.PrependContext(contextName, dockerArgs) : dockerArgs,
            stderr,
            cancellationToken).ConfigureAwait(false);
    }
}
