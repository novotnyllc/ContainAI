namespace ContainAI.Cli.Host;

internal sealed partial class SessionContainerCreateStartOrchestrator
{
    public async Task<ResolutionResult<bool>> StartContainerAsync(
        string context,
        string containerName,
        CancellationToken cancellationToken)
    {
        var start = await dockerClient.StartContainerAsync(
            context,
            containerName,
            cancellationToken).ConfigureAwait(false);
        if (start.ExitCode != 0)
        {
            return ResolutionResult<bool>.ErrorResult(
                $"Failed to start container '{containerName}': {SessionRuntimeInfrastructure.TrimOrFallback(start.StandardError, "docker start failed")}");
        }

        return ResolutionResult<bool>.SuccessResult(true);
    }
}
