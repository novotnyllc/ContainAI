namespace ContainAI.Cli.Host;

internal interface IDockerProxyPortAllocator
{
    Task<string> AllocateSshPortAsync(
        string lockPath,
        string containAiConfigDir,
        string contextName,
        string workspaceName,
        string workspaceSafe,
        CancellationToken cancellationToken);
}

internal sealed partial class DockerProxyPortAllocator : IDockerProxyPortAllocator
{
    private readonly ContainAiDockerProxyOptions options;
    private readonly IContainAiSystemEnvironment environment;
    private readonly IDockerProxyPortAllocationStateReader stateReader;

    public DockerProxyPortAllocator(
        ContainAiDockerProxyOptions options,
        IContainAiSystemEnvironment environment,
        IDockerProxyCommandExecutor commandExecutor)
        : this(options, environment, new DockerProxyPortAllocationStateReader(commandExecutor))
    {
    }

    internal DockerProxyPortAllocator(
        ContainAiDockerProxyOptions options,
        IContainAiSystemEnvironment environment,
        IDockerProxyPortAllocationStateReader stateReader)
    {
        this.options = options;
        this.environment = environment;
        this.stateReader = stateReader;
    }
}
