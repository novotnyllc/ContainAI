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

internal sealed partial class SessionContainerLifecycleService : ISessionContainerLifecycleService
{
    private readonly ISessionSshPortAllocator sshPortAllocator;
    private readonly SessionContainerCreateStartOrchestrator createStartOrchestrator;
    private readonly SessionContainerDockerClient dockerClient;

    public SessionContainerLifecycleService()
        : this(TextWriter.Null, new SessionSshPortAllocator())
    {
    }

    internal SessionContainerLifecycleService(
        TextWriter standardError,
        ISessionSshPortAllocator sessionSshPortAllocator)
    {
        ArgumentNullException.ThrowIfNull(standardError);
        ArgumentNullException.ThrowIfNull(sessionSshPortAllocator);

        sshPortAllocator = sessionSshPortAllocator;

        dockerClient = new SessionContainerDockerClient();
        createStartOrchestrator = new SessionContainerCreateStartOrchestrator(
            standardError,
            sessionSshPortAllocator,
            new SessionContainerRunCommandBuilder(),
            dockerClient,
            new SessionContainerStateWaiter(dockerClient));
    }
}
