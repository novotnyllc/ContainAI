namespace ContainAI.Cli.Host.Sessions.Provisioning;

internal interface ISessionContainerStateWaiter
{
    Task<bool> WaitForContainerStateAsync(
        string context,
        string containerName,
        string desiredState,
        TimeSpan timeout,
        CancellationToken cancellationToken);
}
