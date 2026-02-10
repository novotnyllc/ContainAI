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

        var contextName = environment.GetEnvironmentVariable("CONTAINAI_DOCKER_CONTEXT");
        if (string.IsNullOrWhiteSpace(contextName))
        {
            contextName = options.DefaultContext;
        }

        var wrapperFlags = argumentParser.ParseWrapperFlags(args);
        var dockerArgs = wrapperFlags.DockerArgs;

        if (!argumentParser.IsContainerCreateCommand(dockerArgs))
        {
            var useContainAiContext = await contextSelector.ShouldUseContainAiContextAsync(dockerArgs, contextName, cancellationToken).ConfigureAwait(false);
            return await commandExecutor.RunInteractiveAsync(
                useContainAiContext ? argumentParser.PrependContext(contextName, dockerArgs) : dockerArgs,
                stderr,
                cancellationToken).ConfigureAwait(false);
        }

        var labels = argumentParser.ExtractDevcontainerLabels(dockerArgs);
        if (string.IsNullOrWhiteSpace(labels.ConfigFile) || !featureSettingsParser.TryReadFeatureSettings(labels.ConfigFile!, stderr, out var settings))
        {
            return await commandExecutor.RunInteractiveAsync(dockerArgs, stderr, cancellationToken).ConfigureAwait(false);
        }

        if (!settings.HasContainAiFeature)
        {
            return await commandExecutor.RunInteractiveAsync(dockerArgs, stderr, cancellationToken).ConfigureAwait(false);
        }

        var contextProbe = await commandExecutor.RunCaptureAsync(["context", "inspect", contextName], cancellationToken).ConfigureAwait(false);
        if (contextProbe.ExitCode != 0)
        {
            await stderr.WriteLineAsync("ContainAI: Not set up. Run: cai setup").ConfigureAwait(false);
            return 1;
        }

        var workspaceName = Path.GetFileName(labels.LocalFolder ?? "workspace");
        if (string.IsNullOrWhiteSpace(workspaceName))
        {
            workspaceName = "workspace";
        }

        var workspaceNameSanitized = argumentParser.SanitizeWorkspaceName(workspaceName);
        var containAiConfigDir = Path.Combine(environment.ResolveHomeDirectory(), ".config", "containai");
        var lockPath = Path.Combine(containAiConfigDir, ".ssh-port.lock");

        var sshPort = await portAllocator.AllocateSshPortAsync(
            lockPath,
            containAiConfigDir,
            contextName,
            workspaceName,
            workspaceNameSanitized,
            cancellationToken).ConfigureAwait(false);

        var mountVolume = await volumeCredentialValidator.ValidateAsync(
            contextName,
            settings.DataVolume,
            settings.EnableCredentials,
            wrapperFlags.Quiet,
            stderr,
            cancellationToken).ConfigureAwait(false);

        var modifiedArgs = new List<string>(dockerArgs.Count + 24);
        foreach (var token in dockerArgs)
        {
            modifiedArgs.Add(token);
            if (!string.Equals(token, "run", StringComparison.Ordinal) && !string.Equals(token, "create", StringComparison.Ordinal))
            {
                continue;
            }

            modifiedArgs.Add("--runtime=sysbox-runc");

            if (mountVolume)
            {
                var volumeExists = await commandExecutor.RunCaptureAsync(
                    ["--context", contextName, "volume", "inspect", settings.DataVolume],
                    cancellationToken).ConfigureAwait(false);

                if (volumeExists.ExitCode == 0)
                {
                    modifiedArgs.Add("--mount");
                    modifiedArgs.Add($"type=volume,src={settings.DataVolume},dst=/mnt/agent-data,readonly=false");
                }
                else if (!wrapperFlags.Quiet)
                {
                    await stderr.WriteLineAsync($"[cai-docker] Warning: Data volume {settings.DataVolume} not found - skipping mount").ConfigureAwait(false);
                }
            }

            modifiedArgs.Add("-e");
            modifiedArgs.Add($"CONTAINAI_SSH_PORT={sshPort}");
            modifiedArgs.Add("--label");
            modifiedArgs.Add("containai.managed=true");
            modifiedArgs.Add("--label");
            modifiedArgs.Add("containai.type=devcontainer");
            modifiedArgs.Add("--label");
            modifiedArgs.Add($"containai.devcontainer.workspace={workspaceName}");
            modifiedArgs.Add("--label");
            modifiedArgs.Add($"containai.data-volume={settings.DataVolume}");
            modifiedArgs.Add("--label");
            modifiedArgs.Add($"containai.ssh-port={sshPort}");
            modifiedArgs.Add("--label");
            modifiedArgs.Add($"containai.created={clock.UtcNow:yyyy-MM-ddTHH:mm:ssZ}");
        }

        await sshConfigUpdater.UpdateAsync(workspaceNameSanitized, sshPort, settings.RemoteUser, stderr, cancellationToken).ConfigureAwait(false);

        if (wrapperFlags.Verbose && !wrapperFlags.Quiet)
        {
            await stderr.WriteLineAsync($"[cai-docker] Executing: docker --context {contextName} {string.Join(' ', modifiedArgs)}").ConfigureAwait(false);
        }

        return await commandExecutor.RunInteractiveAsync(
            argumentParser.PrependContext(contextName, modifiedArgs),
            stderr,
            cancellationToken).ConfigureAwait(false);
    }
}
