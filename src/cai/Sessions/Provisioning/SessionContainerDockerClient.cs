namespace ContainAI.Cli.Host;

internal interface ISessionContainerDockerClient
{
    Task<ProcessResult> CreateContainerAsync(string context, IReadOnlyList<string> dockerArgs, CancellationToken cancellationToken);

    Task<ProcessResult> StartContainerAsync(string context, string containerName, CancellationToken cancellationToken);

    Task<ProcessResult> StopContainerAsync(string context, string containerName, CancellationToken cancellationToken);

    Task<ProcessResult> RemoveContainerAsync(string context, string containerName, CancellationToken cancellationToken);

    Task<ProcessResult> InspectContainerStateAsync(string context, string containerName, CancellationToken cancellationToken);
}

internal sealed class SessionContainerDockerClient : ISessionContainerDockerClient
{
    private readonly ISessionRuntimeOperations runtimeOperations;

    public SessionContainerDockerClient()
        : this(new SessionRuntimeOperations())
    {
    }

    internal SessionContainerDockerClient(ISessionRuntimeOperations sessionRuntimeOperations)
        => runtimeOperations = sessionRuntimeOperations ?? throw new ArgumentNullException(nameof(sessionRuntimeOperations));

    public Task<ProcessResult> CreateContainerAsync(string context, IReadOnlyList<string> dockerArgs, CancellationToken cancellationToken)
        => runtimeOperations.DockerCaptureAsync(context, dockerArgs, cancellationToken);

    public Task<ProcessResult> StartContainerAsync(string context, string containerName, CancellationToken cancellationToken)
        => runtimeOperations.DockerCaptureAsync(context, ["start", containerName], cancellationToken);

    public Task<ProcessResult> StopContainerAsync(string context, string containerName, CancellationToken cancellationToken)
        => runtimeOperations.DockerCaptureAsync(context, ["stop", containerName], cancellationToken);

    public Task<ProcessResult> RemoveContainerAsync(string context, string containerName, CancellationToken cancellationToken)
        => runtimeOperations.DockerCaptureAsync(context, ["rm", "-f", containerName], cancellationToken);

    public Task<ProcessResult> InspectContainerStateAsync(string context, string containerName, CancellationToken cancellationToken)
        => runtimeOperations.DockerCaptureAsync(
            context,
            ["inspect", "--format", "{{.State.Status}}", containerName],
            cancellationToken);
}
