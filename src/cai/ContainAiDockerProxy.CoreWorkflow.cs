namespace ContainAI.Cli.Host;

internal sealed partial class ContainAiDockerProxyService
{
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
            var useContainAiContext = await ShouldUseContainAiContextAsync(dockerArgs, contextName, cancellationToken).ConfigureAwait(false);
            return await RunDockerInteractiveAsync(
                useContainAiContext ? argumentParser.PrependContext(contextName, dockerArgs) : dockerArgs,
                stderr,
                cancellationToken).ConfigureAwait(false);
        }

        var labels = argumentParser.ExtractDevcontainerLabels(dockerArgs);
        if (string.IsNullOrWhiteSpace(labels.ConfigFile) || !featureSettingsParser.TryReadFeatureSettings(labels.ConfigFile!, stderr, out var settings))
        {
            return await RunDockerInteractiveAsync(dockerArgs, stderr, cancellationToken).ConfigureAwait(false);
        }

        if (!settings.HasContainAiFeature)
        {
            return await RunDockerInteractiveAsync(dockerArgs, stderr, cancellationToken).ConfigureAwait(false);
        }

        var contextProbe = await RunDockerCaptureAsync(["context", "inspect", contextName], cancellationToken).ConfigureAwait(false);
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

        var sshPort = await WithPortLockAsync(lockPath, () =>
            AllocateSshPortAsync(containAiConfigDir, contextName, workspaceName, workspaceNameSanitized, cancellationToken), cancellationToken).ConfigureAwait(false);

        var mountVolume = await ValidateVolumeCredentialsAsync(
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
                var volumeExists = await RunDockerCaptureAsync(
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

        await UpdateSshConfigAsync(workspaceNameSanitized, sshPort, settings.RemoteUser, stderr, cancellationToken).ConfigureAwait(false);

        if (wrapperFlags.Verbose && !wrapperFlags.Quiet)
        {
            await stderr.WriteLineAsync($"[cai-docker] Executing: docker --context {contextName} {string.Join(' ', modifiedArgs)}").ConfigureAwait(false);
        }

        return await RunDockerInteractiveAsync(
            argumentParser.PrependContext(contextName, modifiedArgs),
            stderr,
            cancellationToken).ConfigureAwait(false);
    }

    private async Task<bool> ShouldUseContainAiContextAsync(IReadOnlyList<string> args, string contextName, CancellationToken cancellationToken)
    {
        foreach (var arg in args)
        {
            if (string.Equals(arg, "--context", StringComparison.Ordinal) || arg.StartsWith("--context=", StringComparison.Ordinal))
            {
                return false;
            }

            if (arg.Contains("devcontainer.", StringComparison.Ordinal) || arg.Contains("containai.", StringComparison.Ordinal))
            {
                return true;
            }
        }

        var subcommand = argumentParser.GetFirstSubcommand(args);
        if (string.IsNullOrWhiteSpace(subcommand))
        {
            return false;
        }

        if (!ContainerTargetingSubcommands.Contains(subcommand))
        {
            return false;
        }

        var containerName = argumentParser.GetContainerNameArg(args, subcommand);
        if (string.IsNullOrWhiteSpace(containerName))
        {
            return false;
        }

        var probe = await RunDockerCaptureAsync(["--context", contextName, "inspect", containerName], cancellationToken).ConfigureAwait(false);
        return probe.ExitCode == 0;
    }
}
