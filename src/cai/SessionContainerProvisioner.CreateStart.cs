using System.Net.NetworkInformation;

namespace ContainAI.Cli.Host;

internal sealed partial class SessionContainerProvisioner
{
    private async Task<ResolutionResult<string>> CreateOrStartContainerAsync(
        SessionCommandOptions options,
        ResolvedTarget resolved,
        ExistingContainerAttachment attachment,
        CancellationToken cancellationToken)
    {
        if (!attachment.Exists)
        {
            var created = await CreateContainerAsync(options, resolved, cancellationToken).ConfigureAwait(false);
            if (!created.Success)
            {
                return ErrorFrom<CreateContainerResult, string>(created);
            }

            return ResolutionResult<string>.SuccessResult(created.Value!.SshPort);
        }

        var sshPort = attachment.SshPort ?? string.Empty;
        if (string.IsNullOrWhiteSpace(sshPort))
        {
            var allocated = await AllocateSshPortAsync(resolved.Context, cancellationToken).ConfigureAwait(false);
            if (!allocated.Success)
            {
                return allocated;
            }

            sshPort = allocated.Value!;
        }

        if (!string.Equals(attachment.State, "running", StringComparison.Ordinal))
        {
            var start = await StartContainerAsync(resolved.Context, resolved.ContainerName, cancellationToken).ConfigureAwait(false);
            if (!start.Success)
            {
                return ErrorFrom<bool, string>(start);
            }
        }

        return ResolutionResult<string>.SuccessResult(sshPort);
    }

    private async Task<ResolutionResult<CreateContainerResult>> CreateContainerAsync(
        SessionCommandOptions options,
        ResolvedTarget resolved,
        CancellationToken cancellationToken)
    {
        var sshPortResolution = await AllocateSshPortAsync(resolved.Context, cancellationToken).ConfigureAwait(false);
        if (!sshPortResolution.Success)
        {
            return ErrorFrom<string, CreateContainerResult>(sshPortResolution);
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
            return ErrorResult<CreateContainerResult>(
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
            return ErrorResult<CreateContainerResult>($"Container '{resolved.ContainerName}' failed to start.");
        }

        return ResolutionResult<CreateContainerResult>.SuccessResult(new CreateContainerResult(sshPort));
    }

    private static async Task<ResolutionResult<bool>> StartContainerAsync(
        string context,
        string containerName,
        CancellationToken cancellationToken)
    {
        var start = await SessionRuntimeInfrastructure.DockerCaptureAsync(
            context,
            ["start", containerName],
            cancellationToken).ConfigureAwait(false);
        if (start.ExitCode != 0)
        {
            return ErrorResult<bool>(
                $"Failed to start container '{containerName}': {SessionRuntimeInfrastructure.TrimOrFallback(start.StandardError, "docker start failed")}");
        }

        return ResolutionResult<bool>.SuccessResult(true);
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

        return ErrorResult<string>(
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
