namespace ContainAI.Cli.Host;

internal sealed partial class SessionContainerCreateStartOrchestrator
{
    public async Task<ResolutionResult<CreateContainerResult>> CreateContainerAsync(
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
        if (!string.IsNullOrWhiteSpace(options.Template))
        {
            await stderr.WriteLineAsync($"Template '{options.Template}' requested; using image '{image}' in native mode.").ConfigureAwait(false);
        }

        var dockerArgs = runCommandBuilder.BuildCommand(options, resolved, sshPort, image);

        var create = await dockerClient.CreateContainerAsync(
            resolved.Context,
            dockerArgs,
            cancellationToken).ConfigureAwait(false);
        if (create.ExitCode != 0)
        {
            return ResolutionResult<CreateContainerResult>.ErrorResult(
                $"Failed to create container: {SessionRuntimeInfrastructure.TrimOrFallback(create.StandardError, "docker run failed")}");
        }

        var waitRunning = await stateWaiter.WaitForContainerStateAsync(
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
}
