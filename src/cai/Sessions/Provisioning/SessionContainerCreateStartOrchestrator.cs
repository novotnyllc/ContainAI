namespace ContainAI.Cli.Host;

internal interface ISessionContainerCreateStartOrchestrator
{
    Task<ResolutionResult<CreateContainerResult>> CreateContainerAsync(
        SessionCommandOptions options,
        ResolvedTarget resolved,
        CancellationToken cancellationToken);

    Task<ResolutionResult<bool>> StartContainerAsync(
        string context,
        string containerName,
        CancellationToken cancellationToken);
}

internal sealed partial class SessionContainerCreateStartOrchestrator : ISessionContainerCreateStartOrchestrator
{
    private readonly TextWriter stderr;
    private readonly ISessionSshPortAllocator sshPortAllocator;
    private readonly ISessionContainerRunCommandBuilder runCommandBuilder;
    private readonly ISessionContainerDockerClient dockerClient;
    private readonly ISessionContainerStateWaiter stateWaiter;

    public SessionContainerCreateStartOrchestrator(
        TextWriter standardError,
        ISessionSshPortAllocator sessionSshPortAllocator,
        ISessionContainerRunCommandBuilder sessionContainerRunCommandBuilder,
        ISessionContainerDockerClient sessionContainerDockerClient,
        ISessionContainerStateWaiter sessionContainerStateWaiter)
    {
        stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));
        sshPortAllocator = sessionSshPortAllocator ?? throw new ArgumentNullException(nameof(sessionSshPortAllocator));
        runCommandBuilder = sessionContainerRunCommandBuilder ?? throw new ArgumentNullException(nameof(sessionContainerRunCommandBuilder));
        dockerClient = sessionContainerDockerClient ?? throw new ArgumentNullException(nameof(sessionContainerDockerClient));
        stateWaiter = sessionContainerStateWaiter ?? throw new ArgumentNullException(nameof(sessionContainerStateWaiter));
    }

}
