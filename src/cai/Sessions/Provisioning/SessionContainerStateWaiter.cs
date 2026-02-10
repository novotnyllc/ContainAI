namespace ContainAI.Cli.Host;

internal interface ISessionContainerStateWaiter
{
    Task<bool> WaitForContainerStateAsync(
        string context,
        string containerName,
        string desiredState,
        TimeSpan timeout,
        CancellationToken cancellationToken);
}

internal sealed class SessionContainerStateWaiter : ISessionContainerStateWaiter
{
    private readonly ISessionContainerDockerClient dockerClient;

    public SessionContainerStateWaiter(ISessionContainerDockerClient sessionContainerDockerClient)
        => dockerClient = sessionContainerDockerClient ?? throw new ArgumentNullException(nameof(sessionContainerDockerClient));

    public async Task<bool> WaitForContainerStateAsync(
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
            var inspect = await dockerClient.InspectContainerStateAsync(context, containerName, cancellationToken).ConfigureAwait(false);
            if (inspect.ExitCode == 0 &&
                string.Equals(inspect.StandardOutput.Trim(), desiredState, StringComparison.Ordinal))
            {
                return true;
            }

            await Task.Delay(TimeSpan.FromMilliseconds(500), cancellationToken).ConfigureAwait(false);
        }

        return false;
    }
}
