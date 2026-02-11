namespace ContainAI.Cli.Host;

internal sealed class DockerProxyCreateWorkflow : IDockerProxyCreateWorkflow
{
    private readonly IDockerProxyArgumentParser argumentParser;
    private readonly IDevcontainerFeatureSettingsParser featureSettingsParser;
    private readonly IDockerProxyCommandExecutor commandExecutor;
    private readonly IDockerProxyPortAllocator portAllocator;
    private readonly IDockerProxyVolumeCredentialValidator volumeCredentialValidator;
    private readonly IDockerProxySshConfigUpdater sshConfigUpdater;
    private readonly IContainAiSystemEnvironment environment;
    private readonly IUtcClock clock;

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
        this.portAllocator = portAllocator;
        this.volumeCredentialValidator = volumeCredentialValidator;
        this.sshConfigUpdater = sshConfigUpdater;
        this.environment = environment;
        this.clock = clock;
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
}
