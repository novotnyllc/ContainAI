namespace ContainAI.Cli.Host;

internal sealed partial class SessionContainerLifecycleService
{
    public async Task RemoveContainerAsync(string context, string containerName, CancellationToken cancellationToken)
    {
        await dockerClient.StopContainerAsync(context, containerName, cancellationToken).ConfigureAwait(false);
        await dockerClient.RemoveContainerAsync(context, containerName, cancellationToken).ConfigureAwait(false);
    }
}
