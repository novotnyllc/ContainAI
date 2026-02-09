using System.Net.NetworkInformation;
using System.Text;

namespace ContainAI.Cli.Host;

internal sealed class SessionContainerProvisioner
{
    private readonly TextWriter stderr;

    public SessionContainerProvisioner(TextWriter standardError) => stderr = standardError;

    public async Task<EnsuredSession> EnsureAsync(
        SessionCommandOptions options,
        ResolvedTarget resolved,
        CancellationToken cancellationToken)
    {
        var labelState = await SessionTargetResolver.ReadContainerLabelsAsync(
            resolved.ContainerName,
            resolved.Context,
            cancellationToken).ConfigureAwait(false);
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

        if (exists &&
            !string.IsNullOrWhiteSpace(options.DataVolume) &&
            !string.Equals(labelState.DataVolume, resolved.DataVolume, StringComparison.Ordinal))
        {
            return EnsuredSession.ErrorResult(
                $"Container '{resolved.ContainerName}' already uses volume '{labelState.DataVolume}'. Use --fresh to recreate with a different volume.");
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
                var start = await SessionRuntimeInfrastructure.DockerCaptureAsync(
                    resolved.Context,
                    ["start", resolved.ContainerName],
                    cancellationToken).ConfigureAwait(false);
                if (start.ExitCode != 0)
                {
                    return EnsuredSession.ErrorResult(
                        $"Failed to start container '{resolved.ContainerName}': {SessionRuntimeInfrastructure.TrimOrFallback(start.StandardError, "docker start failed")}");
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

    private async Task<ResolutionResult<CreateContainerResult>> CreateContainerAsync(
        SessionCommandOptions options,
        ResolvedTarget resolved,
        CancellationToken cancellationToken)
    {
        var sshPortResolution = await AllocateSshPortAsync(resolved.Context, cancellationToken).ConfigureAwait(false);
        if (!sshPortResolution.Success)
        {
            return ResolutionResult<CreateContainerResult>.ErrorResult(sshPortResolution.Error!, sshPortResolution.ErrorCode);
        }

        var sshPort = sshPortResolution.Value!;
        var image = SessionRuntimeInfrastructure.ResolveImage(options);

        var dockerArgs = new List<string>
        {
            "run",
            "--runtime=sysbox-runc",
            "--name", resolved.ContainerName,
            "--hostname", SessionRuntimeInfrastructure.SanitizeHostname(resolved.ContainerName),
            "--label", $"{SessionRuntimeConstants.ManagedLabelKey}={SessionRuntimeConstants.ManagedLabelValue}",
            "--label", $"{SessionRuntimeConstants.WorkspaceLabelKey}={resolved.Workspace}",
            "--label", $"{SessionRuntimeConstants.DataVolumeLabelKey}={resolved.DataVolume}",
            "--label", $"{SessionRuntimeConstants.SshPortLabelKey}={sshPort}",
            "-p", $"{sshPort}:22",
            "-d",
            "--stop-timeout", "100",
            "-v", $"{resolved.DataVolume}:/mnt/agent-data",
            "-v", $"{resolved.Workspace}:/home/agent/workspace",
            "-e", $"CAI_HOST_WORKSPACE={resolved.Workspace}",
            "-e", $"TZ={SessionRuntimeInfrastructure.ResolveHostTimeZone()}",
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

        var create = await SessionRuntimeInfrastructure.DockerCaptureAsync(
            resolved.Context,
            dockerArgs,
            cancellationToken).ConfigureAwait(false);
        if (create.ExitCode != 0)
        {
            return ResolutionResult<CreateContainerResult>.ErrorResult(
                $"Failed to create container: {SessionRuntimeInfrastructure.TrimOrFallback(create.StandardError, "docker run failed")}");
        }

        var waitRunning = await WaitForContainerStateAsync(
            resolved.Context,
            resolved.ContainerName,
            "running",
            TimeSpan.FromSeconds(30),
            cancellationToken).ConfigureAwait(false);
        if (!waitRunning)
        {
            return ResolutionResult<CreateContainerResult>.ErrorResult($"Container '{resolved.ContainerName}' failed to start.");
        }

        return ResolutionResult<CreateContainerResult>.SuccessResult(new CreateContainerResult(sshPort));
    }

    private static async Task<ResolutionResult<bool>> EnsureSshBootstrapAsync(
        ResolvedTarget resolved,
        string sshPort,
        CancellationToken cancellationToken)
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

        var publicKey = await File.ReadAllTextAsync(SessionRuntimeInfrastructure.ResolveSshPublicKeyPath(), cancellationToken).ConfigureAwait(false);
        var keyLine = publicKey.Trim();
        if (string.IsNullOrWhiteSpace(keyLine))
        {
            return ResolutionResult<bool>.ErrorResult("SSH public key is empty.", 12);
        }

        var escapedKey = SessionRuntimeInfrastructure.EscapeForSingleQuotedShell(keyLine);
        var authorize = await SessionRuntimeInfrastructure.DockerCaptureAsync(
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
            return ResolutionResult<bool>.ErrorResult(
                $"Failed to install SSH public key: {SessionRuntimeInfrastructure.TrimOrFallback(authorize.StandardError, "docker exec failed")}",
                12);
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
        var configDir = SessionRuntimeInfrastructure.ResolveSshConfigDir();
        Directory.CreateDirectory(configDir);

        var hostConfigPath = Path.Combine(configDir, $"{containerName}.conf");
        var identityFile = SessionRuntimeInfrastructure.ResolveSshPrivateKeyPath();
        var knownHostsFile = SessionRuntimeInfrastructure.ResolveKnownHostsFilePath();

        var hostEntry = $"""
Host {containerName}
    HostName {SessionRuntimeConstants.SshHost}
    Port {sshPort}
    User agent
    IdentityFile {identityFile}
    IdentitiesOnly yes
    UserKnownHostsFile {knownHostsFile}
    StrictHostKeyChecking accept-new
    AddressFamily inet
""";

        await File.WriteAllTextAsync(hostConfigPath, hostEntry, cancellationToken).ConfigureAwait(false);

        var userSshConfig = Path.Combine(SessionRuntimeInfrastructure.ResolveHomeDirectory(), ".ssh", "config");
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
        var knownHostsFile = SessionRuntimeInfrastructure.ResolveKnownHostsFilePath();
        Directory.CreateDirectory(Path.GetDirectoryName(knownHostsFile)!);
        if (!File.Exists(knownHostsFile))
        {
            await File.WriteAllTextAsync(knownHostsFile, string.Empty, cancellationToken).ConfigureAwait(false);
        }

        var scan = await SessionRuntimeInfrastructure.RunProcessCaptureAsync(
            "ssh-keyscan",
            ["-p", sshPort, "-T", "5", "-t", "rsa,ed25519,ecdsa", SessionRuntimeConstants.SshHost],
            cancellationToken).ConfigureAwait(false);
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
            var alias = SessionRuntimeInfrastructure.ReplaceFirstToken(line, aliasHost);
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
        var configDir = SessionRuntimeInfrastructure.ResolveConfigDirectory();
        Directory.CreateDirectory(configDir);

        var privateKey = SessionRuntimeInfrastructure.ResolveSshPrivateKeyPath();
        var publicKey = SessionRuntimeInfrastructure.ResolveSshPublicKeyPath();

        if (!File.Exists(privateKey) || !File.Exists(publicKey))
        {
            var keygen = await SessionRuntimeInfrastructure.RunProcessCaptureAsync(
                "ssh-keygen",
                ["-t", "ed25519", "-N", string.Empty, "-f", privateKey, "-C", "containai"],
                cancellationToken).ConfigureAwait(false);

            if (keygen.ExitCode != 0)
            {
                return ResolutionResult<bool>.ErrorResult(
                    $"Failed to generate SSH key: {SessionRuntimeInfrastructure.TrimOrFallback(keygen.StandardError, "ssh-keygen failed")}");
            }
        }

        return ResolutionResult<bool>.SuccessResult(true);
    }

    private static async Task<bool> WaitForSshPortAsync(string sshPort, CancellationToken cancellationToken)
    {
        for (var attempt = 0; attempt < 30; attempt++)
        {
            cancellationToken.ThrowIfCancellationRequested();

            var scan = await SessionRuntimeInfrastructure.RunProcessCaptureAsync(
                "ssh-keyscan",
                ["-p", sshPort, "-T", "2", SessionRuntimeConstants.SshHost],
                cancellationToken).ConfigureAwait(false);
            if (scan.ExitCode == 0)
            {
                return true;
            }

            await Task.Delay(TimeSpan.FromMilliseconds(500), cancellationToken).ConfigureAwait(false);
        }

        return false;
    }

    private static async Task<bool> WaitForContainerStateAsync(
        string context,
        string containerName,
        string desiredState,
        TimeSpan timeout,
        CancellationToken cancellationToken)
    {
        var start = DateTimeOffset.UtcNow;
        while (DateTimeOffset.UtcNow - start < timeout)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var inspect = await SessionRuntimeInfrastructure.DockerCaptureAsync(
                context,
                ["inspect", "--format", "{{.State.Status}}", containerName],
                cancellationToken).ConfigureAwait(false);
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
        await SessionRuntimeInfrastructure.DockerCaptureAsync(context, ["stop", containerName], cancellationToken).ConfigureAwait(false);
        await SessionRuntimeInfrastructure.DockerCaptureAsync(context, ["rm", "-f", containerName], cancellationToken).ConfigureAwait(false);
    }

    private static async Task<ResolutionResult<string>> AllocateSshPortAsync(string context, CancellationToken cancellationToken)
    {
        var reservedPorts = new HashSet<int>();

        var reserved = await SessionRuntimeInfrastructure.DockerCaptureAsync(
            context,
            ["ps", "-a", "--filter", $"label={SessionRuntimeConstants.ManagedLabelKey}={SessionRuntimeConstants.ManagedLabelValue}", "--format", $"{{{{index .Labels \"{SessionRuntimeConstants.SshPortLabelKey}\"}}}}"],
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

        for (var port = SessionRuntimeConstants.SshPortRangeStart; port <= SessionRuntimeConstants.SshPortRangeEnd; port++)
        {
            if (!reservedPorts.Contains(port))
            {
                return ResolutionResult<string>.SuccessResult(port.ToString());
            }
        }

        return ResolutionResult<string>.ErrorResult(
            $"No SSH ports available in range {SessionRuntimeConstants.SshPortRangeStart}-{SessionRuntimeConstants.SshPortRangeEnd}.");
    }

    private static async Task<HashSet<int>> GetHostUsedPortsAsync(CancellationToken cancellationToken)
    {
        var ports = new HashSet<int>();

        var ss = await SessionRuntimeInfrastructure.RunProcessCaptureAsync("ss", ["-Htan"], cancellationToken).ConfigureAwait(false);
        if (ss.ExitCode == 0)
        {
            SessionRuntimeInfrastructure.ParsePortsFromSocketTable(ss.StandardOutput, ports);
            return ports;
        }

        var netstat = await SessionRuntimeInfrastructure.RunProcessCaptureAsync("netstat", ["-tan"], cancellationToken).ConfigureAwait(false);
        if (netstat.ExitCode == 0)
        {
            SessionRuntimeInfrastructure.ParsePortsFromSocketTable(netstat.StandardOutput, ports);
        }

        var listeners = IPGlobalProperties.GetIPGlobalProperties().GetActiveTcpListeners();
        foreach (var listener in listeners)
        {
            ports.Add(listener.Port);
        }

        return ports;
    }
}
