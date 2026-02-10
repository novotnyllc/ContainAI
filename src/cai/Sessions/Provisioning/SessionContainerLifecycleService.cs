namespace ContainAI.Cli.Host;

internal interface ISessionContainerLifecycleService
{
    Task<ResolutionResult<string>> CreateOrStartContainerAsync(
        SessionCommandOptions options,
        ResolvedTarget resolved,
        ExistingContainerAttachment attachment,
        CancellationToken cancellationToken);

    Task RemoveContainerAsync(string context, string containerName, CancellationToken cancellationToken);
}

internal sealed class SessionContainerLifecycleService : ISessionContainerLifecycleService
{
    private readonly TextWriter stderr;
    private readonly ISessionSshPortAllocator sshPortAllocator;

    public SessionContainerLifecycleService()
        : this(TextWriter.Null, new SessionSshPortAllocator())
    {
    }

    internal SessionContainerLifecycleService(
        TextWriter standardError,
        ISessionSshPortAllocator sessionSshPortAllocator)
    {
        stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));
        sshPortAllocator = sessionSshPortAllocator ?? throw new ArgumentNullException(nameof(sessionSshPortAllocator));
    }

    public async Task<ResolutionResult<string>> CreateOrStartContainerAsync(
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
                return ResolutionResult<string>.ErrorResult(created.Error!, created.ErrorCode);
            }

            return ResolutionResult<string>.SuccessResult(created.Value!.SshPort);
        }

        var sshPort = attachment.SshPort ?? string.Empty;
        if (string.IsNullOrWhiteSpace(sshPort))
        {
            var allocated = await sshPortAllocator.AllocateSshPortAsync(resolved.Context, cancellationToken).ConfigureAwait(false);
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
                return ResolutionResult<string>.ErrorResult(start.Error!, start.ErrorCode);
            }
        }

        return ResolutionResult<string>.SuccessResult(sshPort);
    }

    public async Task RemoveContainerAsync(string context, string containerName, CancellationToken cancellationToken)
    {
        await SessionRuntimeInfrastructure.DockerCaptureAsync(context, ["stop", containerName], cancellationToken).ConfigureAwait(false);
        await SessionRuntimeInfrastructure.DockerCaptureAsync(context, ["rm", "-f", containerName], cancellationToken).ConfigureAwait(false);
    }

    private async Task<ResolutionResult<CreateContainerResult>> CreateContainerAsync(
        SessionCommandOptions options,
        ResolvedTarget resolved,
        CancellationToken cancellationToken)
    {
        var sshPortResolution = await sshPortAllocator.AllocateSshPortAsync(resolved.Context, cancellationToken).ConfigureAwait(false);
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
            return ResolutionResult<bool>.ErrorResult(
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
}
