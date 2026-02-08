using System.ComponentModel;
using System.Diagnostics;
using System.Security;
using System.Text;
using System.Text.Json;

namespace ContainAI.Cli.Host;

internal sealed class NativeSessionCommandRuntime
{
    private const string DefaultVolume = "containai-data";
    private const string DefaultImageTag = "latest";
    private const string ContainAiRepo = "containai";
    private const string ManagedLabelKey = "containai.managed";
    private const string ManagedLabelValue = "true";
    private const string WorkspaceLabelKey = "containai.workspace";
    private const string DataVolumeLabelKey = "containai.data-volume";
    private const string SshPortLabelKey = "containai.ssh-port";
    private const string SshHost = "127.0.0.1";
    private const int SshPortRangeStart = 2300;
    private const int SshPortRangeEnd = 2500;

    private static readonly string[] ContextFallbackOrder =
    [
        "containai-docker",
        "containai-secure",
        "docker-containai",
    ];

    private static readonly string[] ContainAiImagePrefixes =
    [
        "containai:",
        "ghcr.io/containai/",
        "ghcr.io/novotnyllc/containai",
    ];

    private readonly TextWriter stdout;
    private readonly TextWriter stderr;

    public NativeSessionCommandRuntime(TextWriter standardOutput, TextWriter standardError)
    {
        stdout = standardOutput;
        stderr = standardError;
    }

    public async Task<int> RunRunAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        var parse = ParseRunOptions(args);
        if (!parse.Success)
        {
            await stderr.WriteLineAsync(parse.Error).ConfigureAwait(false);
            return 1;
        }

        if (parse.ShowHelp)
        {
            await stdout.WriteLineAsync(GetRunUsageText()).ConfigureAwait(false);
            return 0;
        }

        return await RunSessionAsync(parse.Options with { Mode = SessionMode.Run }, cancellationToken).ConfigureAwait(false);
    }

    public async Task<int> RunShellAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        var parse = ParseShellOptions(args);
        if (!parse.Success)
        {
            await stderr.WriteLineAsync(parse.Error).ConfigureAwait(false);
            return 1;
        }

        if (parse.ShowHelp)
        {
            await stdout.WriteLineAsync(GetShellUsageText()).ConfigureAwait(false);
            return 0;
        }

        return await RunSessionAsync(parse.Options with { Mode = SessionMode.Shell }, cancellationToken).ConfigureAwait(false);
    }

    public async Task<int> RunExecAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        var parse = ParseExecOptions(args);
        if (!parse.Success)
        {
            await stderr.WriteLineAsync(parse.Error).ConfigureAwait(false);
            return parse.ErrorCode;
        }

        if (parse.ShowHelp)
        {
            await stdout.WriteLineAsync(GetExecUsageText()).ConfigureAwait(false);
            return 0;
        }

        return await RunSessionAsync(parse.Options with { Mode = SessionMode.Exec }, cancellationToken).ConfigureAwait(false);
    }

    private async Task<int> RunSessionAsync(SessionCommandOptions options, CancellationToken cancellationToken)
    {
        var resolved = await ResolveTargetAsync(options, cancellationToken).ConfigureAwait(false);
        if (!string.IsNullOrWhiteSpace(resolved.Error))
        {
            await stderr.WriteLineAsync(resolved.Error).ConfigureAwait(false);
            return resolved.ErrorCode;
        }

        if (options.DryRun)
        {
            await WriteDryRunAsync(options, resolved, cancellationToken).ConfigureAwait(false);
            return 0;
        }

        var ensured = await EnsureContainerAsync(options, resolved, cancellationToken).ConfigureAwait(false);
        if (!string.IsNullOrWhiteSpace(ensured.Error))
        {
            await stderr.WriteLineAsync(ensured.Error).ConfigureAwait(false);
            return ensured.ErrorCode;
        }

        await PersistWorkspaceStateAsync(ensured, cancellationToken).ConfigureAwait(false);

        return options.Mode switch
        {
            SessionMode.Run => await RunRemoteAgentAsync(options, ensured, cancellationToken).ConfigureAwait(false),
            SessionMode.Shell => await RunRemoteShellAsync(options, ensured, cancellationToken).ConfigureAwait(false),
            SessionMode.Exec => await RunRemoteExecAsync(options, ensured, cancellationToken).ConfigureAwait(false),
            _ => 1,
        };
    }

    private static async Task<ResolvedTarget> ResolveTargetAsync(SessionCommandOptions options, CancellationToken cancellationToken)
    {
        if (!string.IsNullOrWhiteSpace(options.Container))
        {
            if (!string.IsNullOrWhiteSpace(options.Workspace))
            {
                return ResolvedTarget.ErrorResult("--container and --workspace are mutually exclusive");
            }

            if (!string.IsNullOrWhiteSpace(options.DataVolume))
            {
                return ResolvedTarget.ErrorResult("--container and --data-volume are mutually exclusive");
            }
        }

        if (options.Mode == SessionMode.Shell && options.Reset)
        {
            if (options.Fresh)
            {
                return ResolvedTarget.ErrorResult("--reset and --fresh are mutually exclusive");
            }

            if (!string.IsNullOrWhiteSpace(options.Container))
            {
                return ResolvedTarget.ErrorResult("--reset and --container are mutually exclusive");
            }

            if (!string.IsNullOrWhiteSpace(options.DataVolume))
            {
                return ResolvedTarget.ErrorResult("--reset and --data-volume are mutually exclusive");
            }
        }

        if (!string.IsNullOrWhiteSpace(options.Container))
        {
            var found = await FindContainerByNameAcrossContextsAsync(options.Container, options.ExplicitConfig, options.Workspace, cancellationToken).ConfigureAwait(false);
            if (!string.IsNullOrWhiteSpace(found.Error))
            {
                return ResolvedTarget.ErrorResult(found.Error, found.ErrorCode);
            }

            if (found.Exists)
            {
                var labels = await ReadContainerLabelsAsync(options.Container, found.Context!, cancellationToken).ConfigureAwait(false);
                if (!labels.IsOwned)
                {
                    var code = options.Mode == SessionMode.Run ? 1 : 15;
                    return ResolvedTarget.ErrorResult($"Container '{options.Container}' exists but was not created by ContainAI", code);
                }

                if (string.IsNullOrWhiteSpace(labels.Workspace))
                {
                    return ResolvedTarget.ErrorResult($"Container {options.Container} is missing workspace label");
                }

                if (string.IsNullOrWhiteSpace(labels.DataVolume))
                {
                    return ResolvedTarget.ErrorResult($"Container {options.Container} is missing data-volume label");
                }

                return new ResolvedTarget(
                    ContainerName: options.Container!,
                    Workspace: labels.Workspace!,
                    DataVolume: labels.DataVolume!,
                    Context: found.Context!,
                    ShouldPersistState: true,
                    CreatedByThisInvocation: false,
                    GeneratedFromReset: false,
                    Error: null,
                    ErrorCode: 1);
            }

            var workspaceInput = options.Workspace ?? Directory.GetCurrentDirectory();
            var workspace = NormalizeWorkspacePath(workspaceInput);
            if (!Directory.Exists(workspace))
            {
                return ResolvedTarget.ErrorResult($"Workspace path does not exist: {workspaceInput}");
            }

            var contextSelection = await ResolveContextForWorkspaceAsync(workspace, options.ExplicitConfig, options.Force, cancellationToken).ConfigureAwait(false);
            if (!contextSelection.Success)
            {
                return ResolvedTarget.ErrorResult(contextSelection.Error!, contextSelection.ErrorCode);
            }

            var volume = await ResolveDataVolumeAsync(workspace, options.DataVolume, options.ExplicitConfig, cancellationToken).ConfigureAwait(false);
            if (!volume.Success)
            {
                return ResolvedTarget.ErrorResult(volume.Error!, volume.ErrorCode);
            }

            return new ResolvedTarget(
                ContainerName: options.Container!,
                Workspace: workspace,
                DataVolume: volume.Value!,
                Context: contextSelection.Context!,
                ShouldPersistState: true,
                CreatedByThisInvocation: true,
                GeneratedFromReset: false,
                Error: null,
                ErrorCode: 1);
        }

        var workspacePathInput = options.Workspace ?? Directory.GetCurrentDirectory();
        var normalizedWorkspace = NormalizeWorkspacePath(workspacePathInput);
        if (!Directory.Exists(normalizedWorkspace))
        {
            return ResolvedTarget.ErrorResult($"Workspace path does not exist: {workspacePathInput}");
        }

        var resolvedVolume = await ResolveDataVolumeAsync(normalizedWorkspace, options.DataVolume, options.ExplicitConfig, cancellationToken).ConfigureAwait(false);
        if (!resolvedVolume.Success)
        {
            return ResolvedTarget.ErrorResult(resolvedVolume.Error!, resolvedVolume.ErrorCode);
        }

        var generatedFromReset = false;
        if (options.Mode == SessionMode.Shell && options.Reset)
        {
            resolvedVolume = ResolutionResult<string>.SuccessResult(GenerateWorkspaceVolumeName(normalizedWorkspace));
            generatedFromReset = true;
            options = options with { Fresh = true };
        }

        var contextResolved = await ResolveContextForWorkspaceAsync(normalizedWorkspace, options.ExplicitConfig, options.Force, cancellationToken).ConfigureAwait(false);
        if (!contextResolved.Success)
        {
            return ResolvedTarget.ErrorResult(contextResolved.Error!, contextResolved.ErrorCode);
        }

        var existing = await FindWorkspaceContainerAsync(normalizedWorkspace, contextResolved.Context!, cancellationToken).ConfigureAwait(false);
        if (!string.IsNullOrWhiteSpace(existing.Error))
        {
            return ResolvedTarget.ErrorResult(existing.Error, existing.ErrorCode);
        }

        var containerName = existing.ContainerName;
        var createdByInvocation = false;
        if (string.IsNullOrWhiteSpace(containerName))
        {
            var generated = await ResolveContainerNameForCreationAsync(normalizedWorkspace, contextResolved.Context!, cancellationToken).ConfigureAwait(false);
            if (!generated.Success)
            {
                return ResolvedTarget.ErrorResult(generated.Error!, generated.ErrorCode);
            }

            containerName = generated.Value;
            createdByInvocation = true;
        }

        return new ResolvedTarget(
            ContainerName: containerName!,
            Workspace: normalizedWorkspace,
            DataVolume: resolvedVolume.Value!,
            Context: contextResolved.Context!,
            ShouldPersistState: true,
            CreatedByThisInvocation: createdByInvocation,
            GeneratedFromReset: generatedFromReset,
            Error: null,
            ErrorCode: 1);
    }

    private async Task<EnsuredSession> EnsureContainerAsync(SessionCommandOptions options, ResolvedTarget resolved, CancellationToken cancellationToken)
    {
        var labelState = await ReadContainerLabelsAsync(resolved.ContainerName, resolved.Context, cancellationToken).ConfigureAwait(false);
        var exists = labelState.Exists;

        if (exists && !labelState.IsOwned)
        {
            var code = options.Mode == SessionMode.Run ? 1 : 15;
            return EnsuredSession.ErrorResult($"Container '{resolved.ContainerName}' exists but was not created by ContainAI", code);
        }

        if (options.Fresh && exists)
        {
            await RemoveContainerAsync(resolved.Context, resolved.ContainerName, cancellationToken).ConfigureAwait(false);
            exists = false;
        }

        if (exists && !string.IsNullOrWhiteSpace(options.DataVolume) && !string.Equals(labelState.DataVolume, resolved.DataVolume, StringComparison.Ordinal))
        {
            return EnsuredSession.ErrorResult($"Container '{resolved.ContainerName}' already uses volume '{labelState.DataVolume}'. Use --fresh to recreate with a different volume.");
        }

        string sshPort;
        if (!exists)
        {
            var created = await CreateContainerAsync(options, resolved, cancellationToken).ConfigureAwait(false);
            if (!created.Success)
            {
                return EnsuredSession.ErrorResult(created.Error!, created.ErrorCode);
            }

            sshPort = created.Value!.SshPort;
        }
        else
        {
            sshPort = labelState.SshPort ?? string.Empty;
            if (string.IsNullOrWhiteSpace(sshPort))
            {
                var allocated = await AllocateSshPortAsync(resolved.Context, cancellationToken).ConfigureAwait(false);
                if (!allocated.Success)
                {
                    return EnsuredSession.ErrorResult(allocated.Error!, allocated.ErrorCode);
                }

                sshPort = allocated.Value!;
            }

            if (!string.Equals(labelState.State, "running", StringComparison.Ordinal))
            {
                var start = await DockerCaptureAsync(resolved.Context, ["start", resolved.ContainerName], cancellationToken).ConfigureAwait(false);
                if (start.ExitCode != 0)
                {
                    return EnsuredSession.ErrorResult($"Failed to start container '{resolved.ContainerName}': {TrimOrFallback(start.StandardError, "docker start failed")}");
                }
            }
        }

        var sshBootstrap = await EnsureSshBootstrapAsync(resolved, sshPort, cancellationToken).ConfigureAwait(false);
        if (!sshBootstrap.Success)
        {
            return EnsuredSession.ErrorResult(sshBootstrap.Error!, sshBootstrap.ErrorCode);
        }

        return new EnsuredSession(
            ContainerName: resolved.ContainerName,
            Workspace: resolved.Workspace,
            DataVolume: resolved.DataVolume,
            Context: resolved.Context,
            SshPort: sshPort,
            Error: null,
            ErrorCode: 1);
    }

    private async Task<int> RunRemoteAgentAsync(SessionCommandOptions options, EnsuredSession session, CancellationToken cancellationToken)
    {
        var runCommand = new List<string>();
        runCommand.AddRange(options.EnvVars);
        if (options.CommandArgs.Count > 0)
        {
            runCommand.AddRange(options.CommandArgs);
        }
        else
        {
            runCommand.Add("claude");
        }

        if (options.Detached)
        {
            var remoteDetached = BuildDetachedRemoteCommand(runCommand);
            var sshResult = await RunSshCaptureAsync(options, session.SshPort, remoteDetached, forceTty: false, cancellationToken).ConfigureAwait(false);
            if (sshResult.ExitCode != 0)
            {
                if (!string.IsNullOrWhiteSpace(sshResult.StandardError))
                {
                    await stderr.WriteLineAsync(sshResult.StandardError.Trim()).ConfigureAwait(false);
                }

                return sshResult.ExitCode;
            }

            var pid = sshResult.StandardOutput.Trim();
            if (!int.TryParse(pid, out _))
            {
                await stderr.WriteLineAsync("Background command failed: could not determine remote PID.").ConfigureAwait(false);
                return 1;
            }

            await stdout.WriteLineAsync($"Command running in background (PID: {pid})").ConfigureAwait(false);
            return 0;
        }

        var remoteForeground = BuildForegroundRemoteCommand(runCommand, loginShell: false);
        var interactiveExit = await RunSshInteractiveAsync(options, session.SshPort, remoteForeground, forceTty: !Console.IsInputRedirected, cancellationToken).ConfigureAwait(false);
        return interactiveExit;
    }

    private static async Task<int> RunRemoteShellAsync(SessionCommandOptions options, EnsuredSession session, CancellationToken cancellationToken)
    {
        const string remoteCommand = "cd /home/agent/workspace && exec $SHELL -l";
        return await RunSshInteractiveAsync(options, session.SshPort, remoteCommand, forceTty: true, cancellationToken).ConfigureAwait(false);
    }

    private async Task<int> RunRemoteExecAsync(SessionCommandOptions options, EnsuredSession session, CancellationToken cancellationToken)
    {
        if (options.CommandArgs.Count == 0)
        {
            await stderr.WriteLineAsync("No command specified. Usage: cai exec [options] [--] <command> [args...]").ConfigureAwait(false);
            return 1;
        }

        var remoteCommand = BuildForegroundRemoteCommand(options.CommandArgs, loginShell: true);
        return await RunSshInteractiveAsync(options, session.SshPort, remoteCommand, forceTty: !Console.IsInputRedirected, cancellationToken).ConfigureAwait(false);
    }

    private async Task WriteDryRunAsync(SessionCommandOptions options, ResolvedTarget resolved, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        await stdout.WriteLineAsync("DRY_RUN=true").ConfigureAwait(false);
        await stdout.WriteLineAsync($"MODE={options.Mode.ToString().ToLowerInvariant()}").ConfigureAwait(false);
        await stdout.WriteLineAsync($"CONTAINER={resolved.ContainerName}").ConfigureAwait(false);
        await stdout.WriteLineAsync($"WORKSPACE={resolved.Workspace}").ConfigureAwait(false);
        await stdout.WriteLineAsync($"DATA_VOLUME={resolved.DataVolume}").ConfigureAwait(false);
        await stdout.WriteLineAsync($"DOCKER_CONTEXT={resolved.Context}").ConfigureAwait(false);
        await stdout.WriteLineAsync($"FRESH={options.Fresh.ToString().ToLowerInvariant()}").ConfigureAwait(false);
        await stdout.WriteLineAsync($"RESET={options.Reset.ToString().ToLowerInvariant()}").ConfigureAwait(false);

        if (options.Mode == SessionMode.Run)
        {
            var command = options.CommandArgs.Count == 0 ? "claude" : string.Join(" ", options.CommandArgs);
            await stdout.WriteLineAsync($"COMMAND={command}").ConfigureAwait(false);
            await stdout.WriteLineAsync($"DETACHED={options.Detached.ToString().ToLowerInvariant()}").ConfigureAwait(false);
        }
        else if (options.Mode == SessionMode.Exec)
        {
            await stdout.WriteLineAsync($"COMMAND={string.Join(" ", options.CommandArgs)}").ConfigureAwait(false);
        }
    }

    private static async Task PersistWorkspaceStateAsync(EnsuredSession session, CancellationToken cancellationToken)
    {
        var configPath = ResolveUserConfigPath();
        Directory.CreateDirectory(Path.GetDirectoryName(configPath)!);
        if (!File.Exists(configPath))
        {
            await File.WriteAllTextAsync(configPath, string.Empty, cancellationToken).ConfigureAwait(false);
        }

        await RunParseTomlAsync(["--file", configPath, "--set-workspace-key", session.Workspace, "container_name", session.ContainerName], cancellationToken).ConfigureAwait(false);

        if (string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("CONTAINAI_DATA_VOLUME")))
        {
            await RunParseTomlAsync(["--file", configPath, "--set-workspace-key", session.Workspace, "data_volume", session.DataVolume], cancellationToken).ConfigureAwait(false);
        }
    }

    private async Task<ResolutionResult<CreateContainerResult>> CreateContainerAsync(SessionCommandOptions options, ResolvedTarget resolved, CancellationToken cancellationToken)
    {
        var sshPortResolution = await AllocateSshPortAsync(resolved.Context, cancellationToken).ConfigureAwait(false);
        if (!sshPortResolution.Success)
        {
            return ResolutionResult<CreateContainerResult>.ErrorResult(sshPortResolution.Error!, sshPortResolution.ErrorCode);
        }

        var sshPort = sshPortResolution.Value!;
        var image = ResolveImage(options);

        var dockerArgs = new List<string>
        {
            "run",
            "--runtime=sysbox-runc",
            "--name", resolved.ContainerName,
            "--hostname", SanitizeHostname(resolved.ContainerName),
            "--label", $"{ManagedLabelKey}={ManagedLabelValue}",
            "--label", $"{WorkspaceLabelKey}={resolved.Workspace}",
            "--label", $"{DataVolumeLabelKey}={resolved.DataVolume}",
            "--label", $"{SshPortLabelKey}={sshPort}",
            "-p", $"{sshPort}:22",
            "-d",
            "--stop-timeout", "100",
            "-v", $"{resolved.DataVolume}:/mnt/agent-data",
            "-v", $"{resolved.Workspace}:/home/agent/workspace",
            "-e", $"CAI_HOST_WORKSPACE={resolved.Workspace}",
            "-e", $"TZ={ResolveHostTimeZone()}",
            "-w", "/home/agent/workspace",
        };

        if (!string.IsNullOrWhiteSpace(options.Memory))
        {
            dockerArgs.Add("--memory");
            dockerArgs.Add(options.Memory);
            dockerArgs.Add("--memory-swap");
            dockerArgs.Add(options.Memory);
        }

        if (!string.IsNullOrWhiteSpace(options.Cpus))
        {
            dockerArgs.Add("--cpus");
            dockerArgs.Add(options.Cpus);
        }

        if (!string.IsNullOrWhiteSpace(options.Template))
        {
            dockerArgs.Add("--label");
            dockerArgs.Add($"ai.containai.template={options.Template}");
            await stderr.WriteLineAsync($"Template '{options.Template}' requested; using image '{image}' in native mode.").ConfigureAwait(false);
        }

        dockerArgs.Add(image);

        var create = await DockerCaptureAsync(resolved.Context, dockerArgs, cancellationToken).ConfigureAwait(false);
        if (create.ExitCode != 0)
        {
            return ResolutionResult<CreateContainerResult>.ErrorResult($"Failed to create container: {TrimOrFallback(create.StandardError, "docker run failed")}");
        }

        var waitRunning = await WaitForContainerStateAsync(resolved.Context, resolved.ContainerName, "running", TimeSpan.FromSeconds(30), cancellationToken).ConfigureAwait(false);
        if (!waitRunning)
        {
            return ResolutionResult<CreateContainerResult>.ErrorResult($"Container '{resolved.ContainerName}' failed to start.");
        }

        return ResolutionResult<CreateContainerResult>.SuccessResult(new CreateContainerResult(sshPort));
    }

    private static async Task<ResolutionResult<bool>> EnsureSshBootstrapAsync(ResolvedTarget resolved, string sshPort, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(sshPort))
        {
            return ResolutionResult<bool>.ErrorResult("Container has no SSH port configured.");
        }

        var keyResult = await EnsureSshKeyPairAsync(cancellationToken).ConfigureAwait(false);
        if (!keyResult.Success)
        {
            return ResolutionResult<bool>.ErrorResult(keyResult.Error!, keyResult.ErrorCode);
        }

        var waitReady = await WaitForSshPortAsync(sshPort, cancellationToken).ConfigureAwait(false);
        if (!waitReady)
        {
            return ResolutionResult<bool>.ErrorResult($"SSH port {sshPort} is not ready for container '{resolved.ContainerName}'.", 12);
        }

        var publicKey = await File.ReadAllTextAsync(ResolveSshPublicKeyPath(), cancellationToken).ConfigureAwait(false);
        var keyLine = publicKey.Trim();
        if (string.IsNullOrWhiteSpace(keyLine))
        {
            return ResolutionResult<bool>.ErrorResult("SSH public key is empty.", 12);
        }

        var escapedKey = EscapeForSingleQuotedShell(keyLine);
        var authorize = await DockerCaptureAsync(
            resolved.Context,
            [
                "exec",
                resolved.ContainerName,
                "sh",
                "-lc",
                $"mkdir -p /home/agent/.ssh && chmod 700 /home/agent/.ssh && touch /home/agent/.ssh/authorized_keys && grep -qxF '{escapedKey}' /home/agent/.ssh/authorized_keys || printf '%s\\n' '{escapedKey}' >> /home/agent/.ssh/authorized_keys; chown -R agent:agent /home/agent/.ssh; chmod 600 /home/agent/.ssh/authorized_keys",
            ],
            cancellationToken).ConfigureAwait(false);

        if (authorize.ExitCode != 0)
        {
            return ResolutionResult<bool>.ErrorResult($"Failed to install SSH public key: {TrimOrFallback(authorize.StandardError, "docker exec failed")}", 12);
        }

        var knownHosts = await UpdateKnownHostsAsync(resolved.ContainerName, sshPort, cancellationToken).ConfigureAwait(false);
        if (!knownHosts.Success)
        {
            return ResolutionResult<bool>.ErrorResult(knownHosts.Error!, knownHosts.ErrorCode);
        }

        var sshConfig = await EnsureSshHostConfigAsync(resolved.ContainerName, sshPort, cancellationToken).ConfigureAwait(false);
        if (!sshConfig.Success)
        {
            return ResolutionResult<bool>.ErrorResult(sshConfig.Error!, sshConfig.ErrorCode);
        }

        return ResolutionResult<bool>.SuccessResult(true);
    }

    private static async Task<ResolutionResult<bool>> EnsureSshHostConfigAsync(string containerName, string sshPort, CancellationToken cancellationToken)
    {
        var configDir = ResolveSshConfigDir();
        Directory.CreateDirectory(configDir);

        var hostConfigPath = Path.Combine(configDir, $"{containerName}.conf");
        var identityFile = ResolveSshPrivateKeyPath();
        var knownHostsFile = ResolveKnownHostsFilePath();

        var hostEntry = $"""
Host {containerName}
    HostName {SshHost}
    Port {sshPort}
    User agent
    IdentityFile {identityFile}
    IdentitiesOnly yes
    UserKnownHostsFile {knownHostsFile}
    StrictHostKeyChecking accept-new
    AddressFamily inet
""";

        await File.WriteAllTextAsync(hostConfigPath, hostEntry, cancellationToken).ConfigureAwait(false);

        var userSshConfig = Path.Combine(ResolveHomeDirectory(), ".ssh", "config");
        Directory.CreateDirectory(Path.GetDirectoryName(userSshConfig)!);
        if (!File.Exists(userSshConfig))
        {
            await File.WriteAllTextAsync(userSshConfig, string.Empty, cancellationToken).ConfigureAwait(false);
        }

        var includeLine = $"Include {configDir}/*.conf";
        var configText = await File.ReadAllTextAsync(userSshConfig, cancellationToken).ConfigureAwait(false);
        if (!configText.Contains(includeLine, StringComparison.Ordinal))
        {
            var builder = new StringBuilder(configText.TrimEnd());
            if (builder.Length > 0)
            {
                builder.AppendLine();
            }

            builder.AppendLine(includeLine);
            await File.WriteAllTextAsync(userSshConfig, builder.ToString(), cancellationToken).ConfigureAwait(false);
        }

        return ResolutionResult<bool>.SuccessResult(true);
    }

    private static async Task<ResolutionResult<bool>> UpdateKnownHostsAsync(string containerName, string sshPort, CancellationToken cancellationToken)
    {
        var knownHostsFile = ResolveKnownHostsFilePath();
        Directory.CreateDirectory(Path.GetDirectoryName(knownHostsFile)!);
        if (!File.Exists(knownHostsFile))
        {
            await File.WriteAllTextAsync(knownHostsFile, string.Empty, cancellationToken).ConfigureAwait(false);
        }

        var scan = await RunProcessCaptureAsync("ssh-keyscan", ["-p", sshPort, "-T", "5", "-t", "rsa,ed25519,ecdsa", SshHost], cancellationToken).ConfigureAwait(false);
        if (scan.ExitCode != 0 || string.IsNullOrWhiteSpace(scan.StandardOutput))
        {
            return ResolutionResult<bool>.ErrorResult("Failed to read SSH host key via ssh-keyscan.", 12);
        }

        var lines = scan.StandardOutput
            .Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Where(static line => !line.StartsWith('#'))
            .Distinct(StringComparer.Ordinal)
            .ToArray();

        var existing = new HashSet<string>(StringComparer.Ordinal);
        foreach (var line in await File.ReadAllLinesAsync(knownHostsFile, cancellationToken).ConfigureAwait(false))
        {
            if (!string.IsNullOrWhiteSpace(line))
            {
                existing.Add(line.Trim());
            }
        }

        var additions = new List<string>();
        foreach (var line in lines)
        {
            if (existing.Add(line))
            {
                additions.Add(line);
            }

            var aliasHost = $"[{containerName}]:{sshPort}";
            var alias = ReplaceFirstToken(line, aliasHost);
            if (existing.Add(alias))
            {
                additions.Add(alias);
            }
        }

        if (additions.Count > 0)
        {
            await File.AppendAllLinesAsync(knownHostsFile, additions, cancellationToken).ConfigureAwait(false);
        }

        return ResolutionResult<bool>.SuccessResult(true);
    }

    private static async Task<ResolutionResult<bool>> EnsureSshKeyPairAsync(CancellationToken cancellationToken)
    {
        var configDir = ResolveConfigDirectory();
        Directory.CreateDirectory(configDir);

        var privateKey = ResolveSshPrivateKeyPath();
        var publicKey = ResolveSshPublicKeyPath();

        if (!File.Exists(privateKey) || !File.Exists(publicKey))
        {
            var keygen = await RunProcessCaptureAsync(
                "ssh-keygen",
                ["-t", "ed25519", "-N", string.Empty, "-f", privateKey, "-C", "containai"],
                cancellationToken).ConfigureAwait(false);

            if (keygen.ExitCode != 0)
            {
                return ResolutionResult<bool>.ErrorResult($"Failed to generate SSH key: {TrimOrFallback(keygen.StandardError, "ssh-keygen failed")}");
            }
        }

        return ResolutionResult<bool>.SuccessResult(true);
    }

    private static async Task<bool> WaitForSshPortAsync(string sshPort, CancellationToken cancellationToken)
    {
        for (var attempt = 0; attempt < 30; attempt++)
        {
            cancellationToken.ThrowIfCancellationRequested();

            var scan = await RunProcessCaptureAsync("ssh-keyscan", ["-p", sshPort, "-T", "2", SshHost], cancellationToken).ConfigureAwait(false);
            if (scan.ExitCode == 0)
            {
                return true;
            }

            await Task.Delay(TimeSpan.FromMilliseconds(500), cancellationToken).ConfigureAwait(false);
        }

        return false;
    }

    private static async Task<bool> WaitForContainerStateAsync(string context, string containerName, string desiredState, TimeSpan timeout, CancellationToken cancellationToken)
    {
        var start = DateTimeOffset.UtcNow;
        while (DateTimeOffset.UtcNow - start < timeout)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var inspect = await DockerCaptureAsync(context, ["inspect", "--format", "{{.State.Status}}", containerName], cancellationToken).ConfigureAwait(false);
            if (inspect.ExitCode == 0 && string.Equals(inspect.StandardOutput.Trim(), desiredState, StringComparison.Ordinal))
            {
                return true;
            }

            await Task.Delay(TimeSpan.FromMilliseconds(500), cancellationToken).ConfigureAwait(false);
        }

        return false;
    }

    private static async Task RemoveContainerAsync(string context, string containerName, CancellationToken cancellationToken)
    {
        await DockerCaptureAsync(context, ["stop", containerName], cancellationToken).ConfigureAwait(false);
        await DockerCaptureAsync(context, ["rm", "-f", containerName], cancellationToken).ConfigureAwait(false);
    }

    private static async Task<ResolutionResult<string>> AllocateSshPortAsync(string context, CancellationToken cancellationToken)
    {
        var reservedPorts = new HashSet<int>();

        var reserved = await DockerCaptureAsync(
            context,
            ["ps", "-a", "--filter", $"label={ManagedLabelKey}={ManagedLabelValue}", "--format", $"{{{{index .Labels \"{SshPortLabelKey}\"}}}}"],
            cancellationToken).ConfigureAwait(false);
        if (reserved.ExitCode == 0)
        {
            foreach (var line in reserved.StandardOutput.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
            {
                if (int.TryParse(line, out var parsed))
                {
                    reservedPorts.Add(parsed);
                }
            }
        }

        foreach (var used in await GetHostUsedPortsAsync(cancellationToken).ConfigureAwait(false))
        {
            reservedPorts.Add(used);
        }

        for (var port = SshPortRangeStart; port <= SshPortRangeEnd; port++)
        {
            if (!reservedPorts.Contains(port))
            {
                return ResolutionResult<string>.SuccessResult(port.ToString());
            }
        }

        return ResolutionResult<string>.ErrorResult($"No SSH ports available in range {SshPortRangeStart}-{SshPortRangeEnd}.");
    }

    private static async Task<HashSet<int>> GetHostUsedPortsAsync(CancellationToken cancellationToken)
    {
        var ports = new HashSet<int>();

        var ss = await RunProcessCaptureAsync("ss", ["-Htan"], cancellationToken).ConfigureAwait(false);
        if (ss.ExitCode == 0)
        {
            ParsePortsFromSocketTable(ss.StandardOutput, ports);
            return ports;
        }

        var netstat = await RunProcessCaptureAsync("netstat", ["-tan"], cancellationToken).ConfigureAwait(false);
        if (netstat.ExitCode == 0)
        {
            ParsePortsFromSocketTable(netstat.StandardOutput, ports);
        }

        return ports;
    }

    private static void ParsePortsFromSocketTable(string content, HashSet<int> destination)
    {
        foreach (var line in content.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            var parts = line.Split(' ', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
            if (parts.Length < 4)
            {
                continue;
            }

            var endpoint = parts[3];
            var separator = endpoint.LastIndexOf(':');
            if (separator <= 0 || separator >= endpoint.Length - 1)
            {
                continue;
            }

            if (int.TryParse(endpoint[(separator + 1)..], out var port) && port > 0)
            {
                destination.Add(port);
            }
        }
    }

    private static async Task<FindContainerByNameResult> FindContainerByNameAcrossContextsAsync(
        string containerName,
        string? explicitConfig,
        string? workspace,
        CancellationToken cancellationToken)
    {
        var contexts = await BuildCandidateContextsAsync(workspace, explicitConfig, cancellationToken).ConfigureAwait(false);
        var found = new List<string>();
        foreach (var context in contexts)
        {
            var inspect = await RunProcessCaptureAsync("docker", ["--context", context, "inspect", "--type", "container", "--", containerName], cancellationToken).ConfigureAwait(false);
            if (inspect.ExitCode == 0)
            {
                found.Add(context);
            }
        }

        if (found.Count == 0)
        {
            return new FindContainerByNameResult(false, null, null, 1);
        }

        if (found.Count > 1)
        {
            return new FindContainerByNameResult(false, null, $"Container '{containerName}' exists in multiple contexts: {string.Join(", ", found)}", 1);
        }

        return new FindContainerByNameResult(true, found[0], null, 1);
    }

    private static async Task<ContainerLookupResult> FindWorkspaceContainerAsync(string workspace, string context, CancellationToken cancellationToken)
    {
        var configPath = ResolveUserConfigPath();
        if (File.Exists(configPath))
        {
            var ws = await RunParseTomlAsync(["--file", configPath, "--get-workspace", workspace], cancellationToken).ConfigureAwait(false);
            if (ws.ExitCode == 0 && !string.IsNullOrWhiteSpace(ws.StandardOutput))
            {
                using var json = JsonDocument.Parse(ws.StandardOutput);
                if (json.RootElement.ValueKind == JsonValueKind.Object &&
                    json.RootElement.TryGetProperty("container_name", out var containerNameElement))
                {
                    var configuredName = containerNameElement.GetString();
                    if (!string.IsNullOrWhiteSpace(configuredName))
                    {
                        var inspect = await DockerCaptureAsync(context, ["inspect", "--type", "container", configuredName], cancellationToken).ConfigureAwait(false);
                        if (inspect.ExitCode == 0)
                        {
                            var labels = await ReadContainerLabelsAsync(configuredName, context, cancellationToken).ConfigureAwait(false);
                            if (string.Equals(labels.Workspace, workspace, StringComparison.Ordinal))
                            {
                                return ContainerLookupResult.Success(configuredName);
                            }
                        }
                    }
                }
            }
        }

        var byLabel = await DockerCaptureAsync(context, ["ps", "-aq", "--filter", $"label={WorkspaceLabelKey}={workspace}"], cancellationToken).ConfigureAwait(false);
        if (byLabel.ExitCode != 0)
        {
            return ContainerLookupResult.Empty();
        }

        var ids = byLabel.StandardOutput.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (ids.Length > 1)
        {
            return ContainerLookupResult.FromError($"Multiple containers found for workspace: {workspace}");
        }

        if (ids.Length == 1)
        {
            var nameResult = await DockerCaptureAsync(context, ["inspect", "--format", "{{.Name}}", ids[0]], cancellationToken).ConfigureAwait(false);
            if (nameResult.ExitCode == 0)
            {
                return ContainerLookupResult.Success(nameResult.StandardOutput.Trim().TrimStart('/'));
            }
        }

        var generated = await GenerateContainerNameAsync(workspace, cancellationToken).ConfigureAwait(false);
        var generatedExists = await DockerCaptureAsync(context, ["inspect", "--type", "container", generated], cancellationToken).ConfigureAwait(false);
        if (generatedExists.ExitCode == 0)
        {
            return ContainerLookupResult.Success(generated);
        }

        var legacy = ContainerNameGenerator.GenerateLegacy(workspace);
        var legacyExists = await DockerCaptureAsync(context, ["inspect", "--type", "container", legacy], cancellationToken).ConfigureAwait(false);
        return legacyExists.ExitCode == 0 ? ContainerLookupResult.Success(legacy) : ContainerLookupResult.Empty();
    }

    private static async Task<ResolutionResult<string>> ResolveContainerNameForCreationAsync(string workspace, string context, CancellationToken cancellationToken)
    {
        var baseName = await GenerateContainerNameAsync(workspace, cancellationToken).ConfigureAwait(false);
        var candidate = baseName;

        for (var suffix = 1; suffix <= 99; suffix++)
        {
            var inspect = await DockerCaptureAsync(context, ["inspect", "--type", "container", candidate], cancellationToken).ConfigureAwait(false);
            if (inspect.ExitCode != 0)
            {
                return ResolutionResult<string>.SuccessResult(candidate);
            }

            var labels = await ReadContainerLabelsAsync(candidate, context, cancellationToken).ConfigureAwait(false);
            if (string.Equals(labels.Workspace, workspace, StringComparison.Ordinal))
            {
                return ResolutionResult<string>.SuccessResult(candidate);
            }

            var suffixText = $"-{suffix + 1}";
            var maxBase = Math.Max(1, 24 - suffixText.Length);
            candidate = TrimTrailingDash(baseName[..Math.Min(baseName.Length, maxBase)]) + suffixText;
        }

        return ResolutionResult<string>.ErrorResult("Too many container name collisions (max 99)");
    }

    private static async Task<string> GenerateContainerNameAsync(string workspace, CancellationToken cancellationToken)
    {
        var repoName = Path.GetFileName(Path.TrimEndingDirectorySeparator(workspace));
        if (string.IsNullOrWhiteSpace(repoName))
        {
            repoName = "repo";
        }

        var branchName = "nogit";
        var gitProbe = await RunProcessCaptureAsync("git", ["-C", workspace, "rev-parse", "--is-inside-work-tree"], cancellationToken).ConfigureAwait(false);
        if (gitProbe.ExitCode == 0)
        {
            var branch = await RunProcessCaptureAsync("git", ["-C", workspace, "rev-parse", "--abbrev-ref", "HEAD"], cancellationToken).ConfigureAwait(false);
            if (branch.ExitCode == 0)
            {
                var value = branch.StandardOutput.Trim();
                branchName = string.IsNullOrWhiteSpace(value) || string.Equals(value, "HEAD", StringComparison.Ordinal) ? "detached" : value;
            }
            else
            {
                branchName = "detached";
            }
        }

        return ContainerNameGenerator.Compose(repoName, branchName);
    }

    private static async Task<ContainerLabelState> ReadContainerLabelsAsync(string containerName, string context, CancellationToken cancellationToken)
    {
        var inspect = await DockerCaptureAsync(
            context,
            [
                "inspect",
                "--format",
                "{{index .Config.Labels \"containai.managed\"}}|{{index .Config.Labels \"containai.workspace\"}}|{{index .Config.Labels \"containai.data-volume\"}}|{{index .Config.Labels \"containai.ssh-port\"}}|{{.Config.Image}}|{{.State.Status}}",
                containerName,
            ],
            cancellationToken).ConfigureAwait(false);

        if (inspect.ExitCode != 0)
        {
            return ContainerLabelState.NotFound();
        }

        var parts = inspect.StandardOutput.Trim().Split('|');
        if (parts.Length < 6)
        {
            return ContainerLabelState.NotFound();
        }

        var managed = string.Equals(parts[0], ManagedLabelValue, StringComparison.Ordinal);
        var image = parts[4];
        var owned = managed || IsContainAiImage(image);

        return new ContainerLabelState(
            Exists: true,
            IsOwned: owned,
            Workspace: NormalizeNoValue(parts[1]),
            DataVolume: NormalizeNoValue(parts[2]),
            SshPort: NormalizeNoValue(parts[3]),
            State: NormalizeNoValue(parts[5]));
    }

    private static bool IsContainAiImage(string image)
    {
        if (string.IsNullOrWhiteSpace(image))
        {
            return false;
        }

        foreach (var prefix in ContainAiImagePrefixes)
        {
            if (image.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }

        return false;
    }

    private static async Task<ContextSelectionResult> ResolveContextForWorkspaceAsync(string workspace, string? explicitConfig, bool force, CancellationToken cancellationToken)
    {
        var configContext = await ResolveConfiguredContextAsync(workspace, explicitConfig, cancellationToken).ConfigureAwait(false);
        if (!string.IsNullOrWhiteSpace(configContext))
        {
            var exists = await DockerContextExistsAsync(configContext, cancellationToken).ConfigureAwait(false);
            if (exists)
            {
                return ContextSelectionResult.FromContext(configContext);
            }
        }

        foreach (var candidate in ContextFallbackOrder)
        {
            if (await DockerContextExistsAsync(candidate, cancellationToken).ConfigureAwait(false))
            {
                return ContextSelectionResult.FromContext(candidate);
            }
        }

        if (force)
        {
            return ContextSelectionResult.FromContext("default");
        }

        return ContextSelectionResult.FromError("No isolation context available. Run 'cai setup' or use --force.");
    }

    private static async Task<List<string>> BuildCandidateContextsAsync(string? workspace, string? explicitConfig, CancellationToken cancellationToken)
    {
        var contexts = new List<string>();
        var configured = await ResolveConfiguredContextAsync(workspace ?? Directory.GetCurrentDirectory(), explicitConfig, cancellationToken).ConfigureAwait(false);
        if (!string.IsNullOrWhiteSpace(configured))
        {
            contexts.Add(configured);
        }

        foreach (var fallback in ContextFallbackOrder)
        {
            if (!contexts.Contains(fallback, StringComparer.Ordinal) && await DockerContextExistsAsync(fallback, cancellationToken).ConfigureAwait(false))
            {
                contexts.Add(fallback);
            }
        }

        if (!contexts.Contains("default", StringComparer.Ordinal))
        {
            contexts.Add("default");
        }

        return contexts;
    }

    private static async Task<string?> ResolveConfiguredContextAsync(string workspace, string? explicitConfig, CancellationToken cancellationToken)
    {
        var configPath = FindConfigFile(workspace, explicitConfig);
        if (string.IsNullOrWhiteSpace(configPath) || !File.Exists(configPath))
        {
            return null;
        }

        var contextResult = await RunParseTomlAsync(["--file", configPath, "--key", "secure_engine.context_name"], cancellationToken).ConfigureAwait(false);
        if (contextResult.ExitCode != 0)
        {
            return null;
        }

        var context = contextResult.StandardOutput.Trim();
        return string.IsNullOrWhiteSpace(context) ? null : context;
    }

    private static async Task<ResolutionResult<string>> ResolveDataVolumeAsync(string workspace, string? explicitVolume, string? explicitConfig, CancellationToken cancellationToken)
    {
        if (!string.IsNullOrWhiteSpace(explicitVolume))
        {
            if (!IsValidVolumeName(explicitVolume))
            {
                return ResolutionResult<string>.ErrorResult($"Invalid volume name: {explicitVolume}");
            }

            return ResolutionResult<string>.SuccessResult(explicitVolume);
        }

        var envVolume = Environment.GetEnvironmentVariable("CONTAINAI_DATA_VOLUME");
        if (!string.IsNullOrWhiteSpace(envVolume))
        {
            if (!IsValidVolumeName(envVolume))
            {
                return ResolutionResult<string>.ErrorResult($"Invalid volume name in CONTAINAI_DATA_VOLUME: {envVolume}");
            }

            return ResolutionResult<string>.SuccessResult(envVolume);
        }

        var userConfig = ResolveUserConfigPath();
        if (File.Exists(userConfig))
        {
            var state = await RunParseTomlAsync(["--file", userConfig, "--get-workspace", workspace], cancellationToken).ConfigureAwait(false);
            if (state.ExitCode == 0 && !string.IsNullOrWhiteSpace(state.StandardOutput))
            {
                using var json = JsonDocument.Parse(state.StandardOutput);
                if (json.RootElement.ValueKind == JsonValueKind.Object &&
                    json.RootElement.TryGetProperty("data_volume", out var volumeElement))
                {
                    var value = volumeElement.GetString();
                    if (!string.IsNullOrWhiteSpace(value) && IsValidVolumeName(value))
                    {
                        return ResolutionResult<string>.SuccessResult(value);
                    }
                }
            }
        }

        var discoveredConfig = FindConfigFile(workspace, explicitConfig);
        if (!string.IsNullOrWhiteSpace(discoveredConfig) && File.Exists(discoveredConfig))
        {
            var localWorkspace = await RunParseTomlAsync(["--file", discoveredConfig, "--get-workspace", workspace], cancellationToken).ConfigureAwait(false);
            if (localWorkspace.ExitCode == 0 && !string.IsNullOrWhiteSpace(localWorkspace.StandardOutput))
            {
                using var json = JsonDocument.Parse(localWorkspace.StandardOutput);
                if (json.RootElement.ValueKind == JsonValueKind.Object &&
                    json.RootElement.TryGetProperty("data_volume", out var wsVolumeElement))
                {
                    var value = wsVolumeElement.GetString();
                    if (!string.IsNullOrWhiteSpace(value) && IsValidVolumeName(value))
                    {
                        return ResolutionResult<string>.SuccessResult(value);
                    }
                }
            }

            var global = await RunParseTomlAsync(["--file", discoveredConfig, "--key", "agent.data_volume"], cancellationToken).ConfigureAwait(false);
            if (global.ExitCode == 0)
            {
                var value = global.StandardOutput.Trim();
                if (!string.IsNullOrWhiteSpace(value) && IsValidVolumeName(value))
                {
                    return ResolutionResult<string>.SuccessResult(value);
                }
            }
        }

        return ResolutionResult<string>.SuccessResult(DefaultVolume);
    }

    private static bool IsValidVolumeName(string name)
    {
        if (string.IsNullOrWhiteSpace(name) || name.Length > 255)
        {
            return false;
        }

        if (!char.IsLetterOrDigit(name[0]))
        {
            return false;
        }

        foreach (var ch in name)
        {
            if (!(char.IsLetterOrDigit(ch) || ch is '_' or '.' or '-'))
            {
                return false;
            }
        }

        return true;
    }

    private static string ResolveImage(SessionCommandOptions options)
    {
        if (!string.IsNullOrWhiteSpace(options.ImageTag) && string.IsNullOrWhiteSpace(options.Template))
        {
            return $"{ContainAiRepo}:{options.ImageTag}";
        }

        if (string.Equals(options.Channel, "nightly", StringComparison.OrdinalIgnoreCase))
        {
            return $"{ContainAiRepo}:nightly";
        }

        return $"{ContainAiRepo}:{DefaultImageTag}";
    }

    private static string NormalizeWorkspacePath(string path) => Path.GetFullPath(ExpandHome(path));

    private static string ExpandHome(string value)
    {
        if (string.IsNullOrWhiteSpace(value) || !value.StartsWith('~'))
        {
            return value;
        }

        var home = ResolveHomeDirectory();
        if (value.Length == 1)
        {
            return home;
        }

        return value[1] switch
        {
            '/' or '\\' => Path.Combine(home, value[2..]),
            _ => value,
        };
    }

    private static string ResolveHomeDirectory()
    {
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        if (string.IsNullOrWhiteSpace(home))
        {
            home = Environment.GetEnvironmentVariable("HOME");
        }

        return string.IsNullOrWhiteSpace(home) ? Directory.GetCurrentDirectory() : home;
    }

    private static string ResolveConfigDirectory()
    {
        var xdgConfig = Environment.GetEnvironmentVariable("XDG_CONFIG_HOME");
        var root = string.IsNullOrWhiteSpace(xdgConfig)
            ? Path.Combine(ResolveHomeDirectory(), ".config")
            : xdgConfig;
        return Path.Combine(root, "containai");
    }

    private static string ResolveUserConfigPath() => Path.Combine(ResolveConfigDirectory(), "config.toml");

    private static string ResolveSshPrivateKeyPath() => Path.Combine(ResolveConfigDirectory(), "id_containai");

    private static string ResolveSshPublicKeyPath() => Path.Combine(ResolveConfigDirectory(), "id_containai.pub");

    private static string ResolveKnownHostsFilePath() => Path.Combine(ResolveConfigDirectory(), "known_hosts");

    private static string ResolveSshConfigDir() => Path.Combine(ResolveHomeDirectory(), ".ssh", "containai.d");

    private static string FindConfigFile(string workspace, string? explicitConfig)
    {
        if (!string.IsNullOrWhiteSpace(explicitConfig))
        {
            return Path.GetFullPath(ExpandHome(explicitConfig));
        }

        var current = Path.GetFullPath(workspace);
        while (!string.IsNullOrWhiteSpace(current))
        {
            var candidate = Path.Combine(current, ".containai", "config.toml");
            if (File.Exists(candidate))
            {
                return candidate;
            }

            if (File.Exists(Path.Combine(current, ".git")) || Directory.Exists(Path.Combine(current, ".git")))
            {
                break;
            }

            var parent = Directory.GetParent(current);
            if (parent is null)
            {
                break;
            }

            current = parent.FullName;
        }

        var userConfig = ResolveUserConfigPath();
        return File.Exists(userConfig) ? userConfig : string.Empty;
    }

    private static string ResolveHostTimeZone()
    {
        try
        {
            return TimeZoneInfo.Local.Id;
        }
        catch (TimeZoneNotFoundException)
        {
            return "UTC";
        }
        catch (InvalidTimeZoneException)
        {
            return "UTC";
        }
        catch (SecurityException)
        {
            return "UTC";
        }
    }

    private static async Task<bool> DockerContextExistsAsync(string context, CancellationToken cancellationToken)
    {
        if (string.Equals(context, "default", StringComparison.Ordinal))
        {
            return true;
        }

        var inspect = await RunProcessCaptureAsync("docker", ["context", "inspect", context], cancellationToken).ConfigureAwait(false);
        return inspect.ExitCode == 0;
    }

    private static async Task<ProcessResult> DockerCaptureAsync(string context, IReadOnlyList<string> dockerArgs, CancellationToken cancellationToken)
    {
        var args = new List<string>();
        if (!string.IsNullOrWhiteSpace(context) && !string.Equals(context, "default", StringComparison.Ordinal))
        {
            args.Add("--context");
            args.Add(context);
        }

        args.AddRange(dockerArgs);
        return await RunProcessCaptureAsync("docker", args, cancellationToken).ConfigureAwait(false);
    }

    private static async Task<int> RunSshInteractiveAsync(
        SessionCommandOptions options,
        string sshPort,
        string remoteCommand,
        bool forceTty,
        CancellationToken cancellationToken)
    {
        var args = BuildSshArguments(options, sshPort, remoteCommand, forceTty);
        return await RunProcessInteractiveAsync("ssh", args, cancellationToken).ConfigureAwait(false);
    }

    private static async Task<ProcessResult> RunSshCaptureAsync(
        SessionCommandOptions options,
        string sshPort,
        string remoteCommand,
        bool forceTty,
        CancellationToken cancellationToken)
    {
        var args = BuildSshArguments(options, sshPort, remoteCommand, forceTty);
        return await RunProcessCaptureAsync("ssh", args, cancellationToken).ConfigureAwait(false);
    }

    private static List<string> BuildSshArguments(SessionCommandOptions options, string sshPort, string remoteCommand, bool forceTty)
    {
        var args = new List<string>
        {
            "-o", $"HostName={SshHost}",
            "-o", $"Port={sshPort}",
            "-o", "User=agent",
            "-o", $"IdentityFile={ResolveSshPrivateKeyPath()}",
            "-o", "IdentitiesOnly=yes",
            "-o", $"UserKnownHostsFile={ResolveKnownHostsFilePath()}",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "PreferredAuthentications=publickey",
            "-o", "GSSAPIAuthentication=no",
            "-o", "PasswordAuthentication=no",
            "-o", "AddressFamily=inet",
            "-o", "ConnectTimeout=10",
        };

        if (options.Quiet)
        {
            args.Add("-q");
        }

        if (options.Verbose)
        {
            args.Add("-v");
        }

        if (forceTty)
        {
            args.Add("-tt");
        }

        args.Add(SshHost);
        args.Add(remoteCommand);
        return args;
    }

    private static string BuildDetachedRemoteCommand(IReadOnlyList<string> commandArgs)
    {
        var inner = JoinForShell(commandArgs);
        return $"cd /home/agent/workspace && nohup {inner} </dev/null >/dev/null 2>&1 & echo $!";
    }

    private static string BuildForegroundRemoteCommand(IReadOnlyList<string> commandArgs, bool loginShell)
    {
        if (!loginShell)
        {
            return $"cd /home/agent/workspace && {JoinForShell(commandArgs)}";
        }

        var inner = JoinForShell(commandArgs);
        var escaped = EscapeForSingleQuotedShell(inner);
        return $"cd /home/agent/workspace && bash -lc '{escaped}'";
    }

    private static string JoinForShell(IReadOnlyList<string> args)
    {
        if (args.Count == 0)
        {
            return "true";
        }

        var escaped = new string[args.Count];
        for (var index = 0; index < args.Count; index++)
        {
            escaped[index] = QuoteBash(args[index]);
        }

        return string.Join(" ", escaped);
    }

    private static string QuoteBash(string value)
    {
        if (string.IsNullOrEmpty(value))
        {
            return "''";
        }

        return $"'{EscapeForSingleQuotedShell(value)}'";
    }

    private static string EscapeForSingleQuotedShell(string value)
        => value.Replace("'", "'\\''", StringComparison.Ordinal);

    private static string ReplaceFirstToken(string knownHostsLine, string hostToken)
    {
        var firstSpace = knownHostsLine.IndexOf(' ');
        if (firstSpace <= 0)
        {
            return knownHostsLine;
        }

        return hostToken + knownHostsLine[firstSpace..];
    }

    private static string NormalizeNoValue(string value)
    {
        var trimmed = value.Trim();
        return string.Equals(trimmed, "<no value>", StringComparison.Ordinal) ? string.Empty : trimmed;
    }

    private static string SanitizeNameComponent(string value, string fallback) => ContainerNameGenerator.SanitizeNameComponent(value, fallback);

    private static string SanitizeHostname(string value)
    {
        var normalized = value.ToLowerInvariant().Replace('_', '-');
        var chars = normalized.Where(static ch => char.IsAsciiLetterOrDigit(ch) || ch == '-').ToArray();
        var cleaned = new string(chars);
        while (cleaned.Contains("--", StringComparison.Ordinal))
        {
            cleaned = cleaned.Replace("--", "-", StringComparison.Ordinal);
        }

        cleaned = cleaned.Trim('-');
        if (cleaned.Length > 63)
        {
            cleaned = cleaned[..63].TrimEnd('-');
        }

        return string.IsNullOrWhiteSpace(cleaned) ? "container" : cleaned;
    }

    private static string TrimTrailingDash(string value) => ContainerNameGenerator.TrimTrailingDash(value);

    private static string GenerateWorkspaceVolumeName(string workspace)
    {
        var repo = SanitizeNameComponent(Path.GetFileName(Path.TrimEndingDirectorySeparator(workspace)), "workspace");
        var branch = "nogit";
        var timestamp = DateTimeOffset.UtcNow.ToString("yyyyMMddHHmmss");

        try
        {
            using var process = new Process
            {
                StartInfo = new ProcessStartInfo("git")
                {
                    UseShellExecute = false,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                },
            };

            process.StartInfo.ArgumentList.Add("-C");
            process.StartInfo.ArgumentList.Add(workspace);
            process.StartInfo.ArgumentList.Add("rev-parse");
            process.StartInfo.ArgumentList.Add("--abbrev-ref");
            process.StartInfo.ArgumentList.Add("HEAD");

            if (process.Start())
            {
                process.WaitForExit(2000);
                if (process.ExitCode == 0)
                {
                    var branchValue = process.StandardOutput.ReadToEnd().Trim();
                    if (!string.IsNullOrWhiteSpace(branchValue))
                    {
                        branch = SanitizeNameComponent(branchValue.Split('/').LastOrDefault() ?? branchValue, "nogit");
                    }
                }
            }
        }
        catch (InvalidOperationException ex)
        {
            // Process startup/read failed; keep default branch token.
            _ = ex;
        }
        catch (Win32Exception ex)
        {
            // Git not available; keep default branch token.
            _ = ex;
        }
        catch (IOException ex)
        {
            // Keep default branch token for reset volume generation.
            _ = ex;
        }

        return $"{repo}-{branch}-{timestamp}";
    }

    private static string TrimOrFallback(string? value, string fallback)
    {
        var trimmed = value?.Trim();
        return string.IsNullOrWhiteSpace(trimmed) ? fallback : trimmed;
    }

    private static string GetRunUsageText() => "Usage: cai run [path] [options] [-- command]";

    private static string GetShellUsageText() => "Usage: cai shell [path] [options]";

    private static string GetExecUsageText() => "Usage: cai exec [options] [--] <command> [args...]";

    private static ParseResult ParseRunOptions(IReadOnlyList<string> args)
    {
        var options = SessionCommandOptions.Create(SessionMode.Run);
        var index = 1;

        while (index < args.Count)
        {
            var token = args[index];
            switch (token)
            {
                case "--":
                    options = options with { CommandArgs = args.Skip(index + 1).ToArray() };
                    return ParseResult.SuccessResult(options);
                case "--help":
                case "-h":
                    return ParseResult.HelpResult(options);
                case "--credentials":
                    if (!TryReadValue(args, ref index, out var credentials))
                    {
                        return ParseResult.ErrorResult("--credentials requires a value");
                    }

                    options = options with { Credentials = credentials };
                    break;
                case "--acknowledge-credential-risk":
                    options = options with { AcknowledgeCredentialRisk = true };
                    break;
                case "--data-volume":
                    if (!TryReadValue(args, ref index, out var dataVolume))
                    {
                        return ParseResult.ErrorResult("--data-volume requires a value");
                    }

                    options = options with { DataVolume = dataVolume };
                    break;
                case "--config":
                    if (!TryReadValue(args, ref index, out var config))
                    {
                        return ParseResult.ErrorResult("--config requires a value");
                    }

                    options = options with { ExplicitConfig = config };
                    break;
                case "--workspace":
                case "-w":
                    if (!TryReadValue(args, ref index, out var workspace))
                    {
                        return ParseResult.ErrorResult("--workspace requires a value");
                    }

                    options = options with { Workspace = workspace };
                    break;
                default:
                    if (token.StartsWith("--workspace=", StringComparison.Ordinal))
                    {
                        options = options with { Workspace = token[12..] };
                    }
                    else if (token.StartsWith("-w", StringComparison.Ordinal) && token.Length > 2)
                    {
                        options = options with { Workspace = token[2..] };
                    }
                    else if (token == "--container")
                    {
                        if (!TryReadValue(args, ref index, out var container))
                        {
                            return ParseResult.ErrorResult("--container requires a value");
                        }

                        options = options with { Container = container };
                    }
                    else if (token.StartsWith("--container=", StringComparison.Ordinal))
                    {
                        options = options with { Container = token[12..] };
                    }
                    else if (token is "--restart" or "--fresh")
                    {
                        options = options with { Fresh = true };
                    }
                    else if (token == "--force")
                    {
                        options = options with { Force = true };
                    }
                    else if (token is "--detached" or "-d")
                    {
                        options = options with { Detached = true };
                    }
                    else if (token is "--quiet" or "-q")
                    {
                        options = options with { Quiet = true };
                    }
                    else if (token == "--verbose")
                    {
                        options = options with { Verbose = true };
                    }
                    else if (token is "--debug" or "-D")
                    {
                        options = options with { Debug = true };
                    }
                    else if (token == "--dry-run")
                    {
                        options = options with { DryRun = true };
                    }
                    else if (token == "--image-tag")
                    {
                        if (!TryReadValue(args, ref index, out var imageTag))
                        {
                            return ParseResult.ErrorResult("--image-tag requires a value");
                        }

                        options = options with { ImageTag = imageTag };
                    }
                    else if (token.StartsWith("--image-tag=", StringComparison.Ordinal))
                    {
                        options = options with { ImageTag = token[("--image-tag=".Length)..] };
                    }
                    else if (token == "--template")
                    {
                        if (!TryReadValue(args, ref index, out var template))
                        {
                            return ParseResult.ErrorResult("--template requires a value");
                        }

                        options = options with { Template = template };
                    }
                    else if (token.StartsWith("--template=", StringComparison.Ordinal))
                    {
                        options = options with { Template = token[("--template=".Length)..] };
                    }
                    else if (token == "--channel")
                    {
                        if (!TryReadValue(args, ref index, out var channel))
                        {
                            return ParseResult.ErrorResult("--channel requires a value");
                        }

                        options = options with { Channel = channel };
                    }
                    else if (token.StartsWith("--channel=", StringComparison.Ordinal))
                    {
                        options = options with { Channel = token[("--channel=".Length)..] };
                    }
                    else if (token == "--memory")
                    {
                        if (!TryReadValue(args, ref index, out var memory))
                        {
                            return ParseResult.ErrorResult("--memory requires a value");
                        }

                        options = options with { Memory = memory };
                    }
                    else if (token.StartsWith("--memory=", StringComparison.Ordinal))
                    {
                        options = options with { Memory = token[("--memory=".Length)..] };
                    }
                    else if (token == "--cpus")
                    {
                        if (!TryReadValue(args, ref index, out var cpus))
                        {
                            return ParseResult.ErrorResult("--cpus requires a value");
                        }

                        options = options with { Cpus = cpus };
                    }
                    else if (token.StartsWith("--cpus=", StringComparison.Ordinal))
                    {
                        options = options with { Cpus = token[("--cpus=".Length)..] };
                    }
                    else if (token is "--mount-docker-socket" or "--please-root-my-host" or "--allow-host-credentials" or "--i-understand-this-exposes-host-credentials" or "--allow-host-docker-socket" or "--i-understand-this-grants-root-access")
                    {
                        return ParseResult.ErrorResult($"{token} is no longer supported in cai run");
                    }
                    else if (token is "--volume" or "-v" || token.StartsWith("--volume=", StringComparison.Ordinal) || (token.StartsWith("-v", StringComparison.Ordinal) && token.Length > 2))
                    {
                        return ParseResult.ErrorResult("--volume is not supported in containai run");
                    }
                    else if (token is "--env" or "-e")
                    {
                        if (!TryReadValue(args, ref index, out var envVar))
                        {
                            return ParseResult.ErrorResult("--env requires a value");
                        }

                        options.EnvVars.Add(envVar);
                    }
                    else if (token.StartsWith("--env=", StringComparison.Ordinal))
                    {
                        options.EnvVars.Add(token[("--env=".Length)..]);
                    }
                    else if (token.StartsWith("-e", StringComparison.Ordinal) && token.Length > 2)
                    {
                        options.EnvVars.Add(token[2..]);
                    }
                    else if (!token.StartsWith('-') && string.IsNullOrWhiteSpace(options.Workspace) && Directory.Exists(ExpandHome(token)))
                    {
                        options = options with { Workspace = token };
                    }
                    else
                    {
                        return ParseResult.ErrorResult($"Unknown option: {token}");
                    }

                    break;
            }

            index++;
        }

        return ParseResult.SuccessResult(options);
    }

    private static ParseResult ParseShellOptions(IReadOnlyList<string> args)
    {
        var options = SessionCommandOptions.Create(SessionMode.Shell);
        var index = 1;

        while (index < args.Count)
        {
            var token = args[index];
            switch (token)
            {
                case "--help":
                case "-h":
                    return ParseResult.HelpResult(options);
                case "--data-volume":
                    if (!TryReadValue(args, ref index, out var dataVolume))
                    {
                        return ParseResult.ErrorResult("--data-volume requires a value");
                    }

                    options = options with { DataVolume = dataVolume };
                    break;
                case "--config":
                    if (!TryReadValue(args, ref index, out var config))
                    {
                        return ParseResult.ErrorResult("--config requires a value");
                    }

                    options = options with { ExplicitConfig = config };
                    break;
                case "--workspace":
                case "-w":
                    if (!TryReadValue(args, ref index, out var workspace))
                    {
                        return ParseResult.ErrorResult("--workspace requires a value");
                    }

                    options = options with { Workspace = workspace };
                    break;
                default:
                    if (token.StartsWith("--workspace=", StringComparison.Ordinal))
                    {
                        options = options with { Workspace = token[12..] };
                    }
                    else if (token.StartsWith("-w", StringComparison.Ordinal) && token.Length > 2)
                    {
                        options = options with { Workspace = token[2..] };
                    }
                    else if (token == "--container")
                    {
                        if (!TryReadValue(args, ref index, out var container))
                        {
                            return ParseResult.ErrorResult("--container requires a value");
                        }

                        options = options with { Container = container };
                    }
                    else if (token.StartsWith("--container=", StringComparison.Ordinal))
                    {
                        options = options with { Container = token[12..] };
                    }
                    else if (token is "--restart" or "--fresh")
                    {
                        options = options with { Fresh = true };
                    }
                    else if (token == "--reset")
                    {
                        options = options with { Reset = true };
                    }
                    else if (token == "--force")
                    {
                        options = options with { Force = true };
                    }
                    else if (token is "--quiet" or "-q")
                    {
                        options = options with { Quiet = true };
                    }
                    else if (token == "--verbose")
                    {
                        options = options with { Verbose = true };
                    }
                    else if (token is "--debug" or "-D")
                    {
                        options = options with { Debug = true };
                    }
                    else if (token == "--dry-run")
                    {
                        options = options with { DryRun = true };
                    }
                    else if (token == "--image-tag")
                    {
                        if (!TryReadValue(args, ref index, out var imageTag))
                        {
                            return ParseResult.ErrorResult("--image-tag requires a value");
                        }

                        options = options with { ImageTag = imageTag };
                    }
                    else if (token.StartsWith("--image-tag=", StringComparison.Ordinal))
                    {
                        options = options with { ImageTag = token[("--image-tag=".Length)..] };
                    }
                    else if (token == "--template")
                    {
                        if (!TryReadValue(args, ref index, out var template))
                        {
                            return ParseResult.ErrorResult("--template requires a value");
                        }

                        options = options with { Template = template };
                    }
                    else if (token.StartsWith("--template=", StringComparison.Ordinal))
                    {
                        options = options with { Template = token[("--template=".Length)..] };
                    }
                    else if (token == "--channel")
                    {
                        if (!TryReadValue(args, ref index, out var channel))
                        {
                            return ParseResult.ErrorResult("--channel requires a value");
                        }

                        options = options with { Channel = channel };
                    }
                    else if (token.StartsWith("--channel=", StringComparison.Ordinal))
                    {
                        options = options with { Channel = token[("--channel=".Length)..] };
                    }
                    else if (token == "--memory")
                    {
                        if (!TryReadValue(args, ref index, out var memory))
                        {
                            return ParseResult.ErrorResult("--memory requires a value");
                        }

                        options = options with { Memory = memory };
                    }
                    else if (token.StartsWith("--memory=", StringComparison.Ordinal))
                    {
                        options = options with { Memory = token[("--memory=".Length)..] };
                    }
                    else if (token == "--cpus")
                    {
                        if (!TryReadValue(args, ref index, out var cpus))
                        {
                            return ParseResult.ErrorResult("--cpus requires a value");
                        }

                        options = options with { Cpus = cpus };
                    }
                    else if (token.StartsWith("--cpus=", StringComparison.Ordinal))
                    {
                        options = options with { Cpus = token[("--cpus=".Length)..] };
                    }
                    else if (token is "--mount-docker-socket" or "--please-root-my-host" or "--allow-host-credentials" or "--i-understand-this-exposes-host-credentials" or "--allow-host-docker-socket" or "--i-understand-this-grants-root-access")
                    {
                        return ParseResult.ErrorResult($"{token} is not supported in cai shell");
                    }
                    else if (token is "--env" or "-e" || token.StartsWith("--env=", StringComparison.Ordinal) || (token.StartsWith("-e", StringComparison.Ordinal) && token.Length > 2))
                    {
                        return ParseResult.ErrorResult("--env is not supported in cai shell (SSH mode)");
                    }
                    else if (token is "--volume" or "-v" || token.StartsWith("--volume=", StringComparison.Ordinal) || (token.StartsWith("-v", StringComparison.Ordinal) && token.Length > 2))
                    {
                        return ParseResult.ErrorResult("--volume is not supported in cai shell (SSH mode)");
                    }
                    else if (!token.StartsWith('-') && string.IsNullOrWhiteSpace(options.Workspace) && Directory.Exists(ExpandHome(token)))
                    {
                        options = options with { Workspace = token };
                    }
                    else
                    {
                        return ParseResult.ErrorResult($"Unknown option: {token}");
                    }

                    break;
            }

            index++;
        }

        return ParseResult.SuccessResult(options);
    }

    private static ParseResult ParseExecOptions(IReadOnlyList<string> args)
    {
        var options = SessionCommandOptions.Create(SessionMode.Exec);
        var command = new List<string>();
        var index = 1;

        while (index < args.Count)
        {
            var token = args[index];

            if (token == "--")
            {
                command.AddRange(args.Skip(index + 1));
                break;
            }

            if (command.Count > 0)
            {
                command.Add(token);
                index++;
                continue;
            }

            switch (token)
            {
                case "--help":
                case "-h":
                    return ParseResult.HelpResult(options);
                case "--workspace":
                case "-w":
                    if (!TryReadValue(args, ref index, out var workspace))
                    {
                        return ParseResult.ErrorResult("--workspace requires a value");
                    }

                    options = options with { Workspace = workspace };
                    break;
                case "--container":
                    if (!TryReadValue(args, ref index, out var container))
                    {
                        return ParseResult.ErrorResult("--container requires a value");
                    }

                    options = options with { Container = container };
                    break;
                case "--template":
                    if (!TryReadValue(args, ref index, out var template))
                    {
                        return ParseResult.ErrorResult("--template requires a value");
                    }

                    options = options with { Template = template };
                    break;
                case "--channel":
                    if (!TryReadValue(args, ref index, out var channel))
                    {
                        return ParseResult.ErrorResult("--channel requires a value");
                    }

                    options = options with { Channel = channel };
                    break;
                case "--data-volume":
                    if (!TryReadValue(args, ref index, out var dataVolume))
                    {
                        return ParseResult.ErrorResult("--data-volume requires a value");
                    }

                    options = options with { DataVolume = dataVolume };
                    break;
                case "--config":
                    if (!TryReadValue(args, ref index, out var config))
                    {
                        return ParseResult.ErrorResult("--config requires a value");
                    }

                    options = options with { ExplicitConfig = config };
                    break;
                case "--fresh":
                    options = options with { Fresh = true };
                    break;
                case "--restart":
                    return ParseResult.ErrorResult("--restart is not supported in cai exec", 1);
                case "--force":
                    options = options with { Force = true };
                    break;
                case "--quiet":
                case "-q":
                    options = options with { Quiet = true };
                    break;
                case "--verbose":
                    options = options with { Verbose = true };
                    break;
                case "--debug":
                case "-D":
                    options = options with { Debug = true };
                    break;
                default:
                    if (token.StartsWith("--workspace=", StringComparison.Ordinal))
                    {
                        options = options with { Workspace = token[12..] };
                    }
                    else if (token.StartsWith("-w", StringComparison.Ordinal) && token.Length > 2)
                    {
                        options = options with { Workspace = token[2..] };
                    }
                    else if (token.StartsWith("--container=", StringComparison.Ordinal))
                    {
                        options = options with { Container = token[("--container=".Length)..] };
                    }
                    else if (token.StartsWith("--template=", StringComparison.Ordinal))
                    {
                        options = options with { Template = token[("--template=".Length)..] };
                    }
                    else if (token.StartsWith("--channel=", StringComparison.Ordinal))
                    {
                        options = options with { Channel = token[("--channel=".Length)..] };
                    }
                    else if (token.StartsWith("--data-volume=", StringComparison.Ordinal))
                    {
                        options = options with { DataVolume = token[("--data-volume=".Length)..] };
                    }
                    else if (token.StartsWith("--config=", StringComparison.Ordinal))
                    {
                        options = options with { ExplicitConfig = token[("--config=".Length)..] };
                    }
                    else if (token.StartsWith('-'))
                    {
                        command.AddRange(args.Skip(index));
                        index = args.Count;
                        continue;
                    }
                    else
                    {
                        command.AddRange(args.Skip(index));
                        index = args.Count;
                        continue;
                    }

                    break;
            }

            index++;
        }

        if (command.Count == 0)
        {
            return ParseResult.ErrorResult("No command specified", 1);
        }

        options = options with { CommandArgs = command };
        return ParseResult.SuccessResult(options);
    }

    private static bool TryReadValue(IReadOnlyList<string> args, ref int index, out string value)
    {
        value = string.Empty;
        if (index + 1 >= args.Count)
        {
            return false;
        }

        value = ExpandHome(args[index + 1]);
        index++;
        return true;
    }

    private static async Task<ProcessResult> RunParseTomlAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var result = TomlCommandProcessor.Execute(args);
        return new ProcessResult(result.ExitCode, result.StandardOutput, result.StandardError);
    }

    private static async Task<int> RunProcessInteractiveAsync(string fileName, IReadOnlyList<string> arguments, CancellationToken cancellationToken)
    {
        using var process = new Process
        {
            StartInfo = new ProcessStartInfo(fileName)
            {
                UseShellExecute = false,
            },
        };

        foreach (var arg in arguments)
        {
            process.StartInfo.ArgumentList.Add(arg);
        }

        try
        {
            if (!process.Start())
            {
                return 127;
            }
        }
        catch (Win32Exception ex)
        {
            await Console.Error.WriteLineAsync($"Failed to start '{fileName}': {ex.Message}").ConfigureAwait(false);
            return 127;
        }

        using var cancellationRegistration = cancellationToken.Register(() =>
        {
            try
            {
                if (!process.HasExited)
                {
                    process.Kill(entireProcessTree: true);
                }
            }
            catch (InvalidOperationException ex)
            {
                // Process exited between HasExited check and Kill.
                _ = ex;
            }
            catch (Win32Exception ex)
            {
                // Ignore cleanup failures.
                _ = ex;
            }
        });

        await process.WaitForExitAsync(cancellationToken).ConfigureAwait(false);
        return process.ExitCode;
    }

    private static async Task<ProcessResult> RunProcessCaptureAsync(string fileName, IReadOnlyList<string> arguments, CancellationToken cancellationToken)
    {
        using var process = new Process
        {
            StartInfo = new ProcessStartInfo(fileName)
            {
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
            },
        };

        foreach (var arg in arguments)
        {
            process.StartInfo.ArgumentList.Add(arg);
        }

        try
        {
            if (!process.Start())
            {
                return new ProcessResult(127, string.Empty, $"Failed to launch process '{fileName}'.");
            }
        }
        catch (Win32Exception ex)
        {
            return new ProcessResult(127, string.Empty, ex.Message);
        }

        using var cancellationRegistration = cancellationToken.Register(() =>
        {
            try
            {
                if (!process.HasExited)
                {
                    process.Kill(entireProcessTree: true);
                }
            }
            catch (InvalidOperationException ex)
            {
                // Process exited between HasExited check and Kill.
                _ = ex;
            }
            catch (Win32Exception ex)
            {
                // Ignore cleanup failures.
                _ = ex;
            }
        });

        var stdOutTask = process.StandardOutput.ReadToEndAsync(cancellationToken);
        var stdErrTask = process.StandardError.ReadToEndAsync(cancellationToken);
        await process.WaitForExitAsync(cancellationToken).ConfigureAwait(false);

        return new ProcessResult(
            process.ExitCode,
            await stdOutTask.ConfigureAwait(false),
            await stdErrTask.ConfigureAwait(false));
    }

    private enum SessionMode
    {
        Run,
        Shell,
        Exec,
    }

    private sealed record SessionCommandOptions(
        SessionMode Mode,
        string? Workspace,
        string? DataVolume,
        string? ExplicitConfig,
        string? Container,
        string? Template,
        string? ImageTag,
        string? Channel,
        string? Memory,
        string? Cpus,
        string? Credentials,
        bool AcknowledgeCredentialRisk,
        bool Fresh,
        bool Reset,
        bool Force,
        bool Detached,
        bool Quiet,
        bool Verbose,
        bool Debug,
        bool DryRun,
        IReadOnlyList<string> CommandArgs,
        List<string> EnvVars)
    {
        public static SessionCommandOptions Create(SessionMode mode)
            => new(
                Mode: mode,
                Workspace: null,
                DataVolume: null,
                ExplicitConfig: null,
                Container: null,
                Template: null,
                ImageTag: null,
                Channel: null,
                Memory: null,
                Cpus: null,
                Credentials: null,
                AcknowledgeCredentialRisk: false,
                Fresh: false,
                Reset: false,
                Force: false,
                Detached: false,
                Quiet: false,
                Verbose: false,
                Debug: false,
                DryRun: false,
                CommandArgs: Array.Empty<string>(),
                EnvVars: []);
    }

    private sealed record ParseResult(bool Success, bool ShowHelp, SessionCommandOptions Options, string Error, int ErrorCode)
    {
        public static ParseResult SuccessResult(SessionCommandOptions options) => new(true, false, options, string.Empty, 1);

        public static ParseResult HelpResult(SessionCommandOptions options) => new(true, true, options, string.Empty, 0);

        public static ParseResult ErrorResult(string error, int errorCode = 1)
            => new(false, false, SessionCommandOptions.Create(SessionMode.Run), error, errorCode);
    }

    private sealed record ResolutionResult<T>(bool Success, T? Value, string? Error, int ErrorCode)
    {
        public static ResolutionResult<T> SuccessResult(T value) => new(true, value, null, 1);

        public static ResolutionResult<T> ErrorResult(string error, int errorCode = 1) => new(false, default, error, errorCode);
    }

    private sealed record ContextSelectionResult(bool Success, string? Context, string? Error, int ErrorCode)
    {
        public static ContextSelectionResult FromContext(string context) => new(true, context, null, 1);

        public static ContextSelectionResult FromError(string error, int errorCode = 1) => new(false, null, error, errorCode);
    }

    private sealed record FindContainerByNameResult(bool Exists, string? Context, string? Error, int ErrorCode);

    private sealed record ContainerLookupResult(string? ContainerName, string? Error, int ErrorCode)
    {
        public static ContainerLookupResult Success(string name) => new(name, null, 1);

        public static ContainerLookupResult Empty() => new(null, null, 1);

        public static ContainerLookupResult FromError(string error, int errorCode = 1) => new(null, error, errorCode);
    }

    private sealed record ResolvedTarget(
        string ContainerName,
        string Workspace,
        string DataVolume,
        string Context,
        bool ShouldPersistState,
        bool CreatedByThisInvocation,
        bool GeneratedFromReset,
        string? Error,
        int ErrorCode)
    {
        public static ResolvedTarget ErrorResult(string error, int errorCode = 1)
            => new(string.Empty, string.Empty, string.Empty, string.Empty, false, false, false, error, errorCode);
    }

    private sealed record EnsuredSession(
        string ContainerName,
        string Workspace,
        string DataVolume,
        string Context,
        string SshPort,
        string? Error,
        int ErrorCode)
    {
        public static EnsuredSession ErrorResult(string error, int errorCode = 1)
            => new(string.Empty, string.Empty, string.Empty, string.Empty, string.Empty, error, errorCode);
    }

    private sealed record CreateContainerResult(string SshPort);

    private sealed record ContainerLabelState(bool Exists, bool IsOwned, string Workspace, string DataVolume, string SshPort, string State)
    {
        public static ContainerLabelState NotFound() => new(false, false, string.Empty, string.Empty, string.Empty, string.Empty);
    }

    private readonly record struct ProcessResult(int ExitCode, string StandardOutput, string StandardError);
}
