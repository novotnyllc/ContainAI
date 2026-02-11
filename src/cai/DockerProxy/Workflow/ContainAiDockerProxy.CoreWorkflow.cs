namespace ContainAI.Cli.Host;

internal sealed class ContainAiDockerProxyService : IContainAiDockerProxyService
{
    private readonly ContainAiDockerProxyOptions options;
    private readonly IDockerProxyArgumentParser argumentParser;
    private readonly IDockerProxyCreateWorkflow createWorkflow;
    private readonly IDockerProxyPassthroughWorkflow passthroughWorkflow;
    private readonly IContainAiSystemEnvironment environment;

    public ContainAiDockerProxyService(
        ContainAiDockerProxyOptions options,
        IDockerProxyArgumentParser argumentParser,
        IDockerProxyCreateWorkflow createWorkflow,
        IDockerProxyPassthroughWorkflow passthroughWorkflow,
        IContainAiSystemEnvironment environment)
    {
        this.options = options;
        this.argumentParser = argumentParser;
        this.createWorkflow = createWorkflow;
        this.passthroughWorkflow = passthroughWorkflow;
        this.environment = environment;
    }

    public async Task<int> RunAsync(IReadOnlyList<string> args, TextWriter stdout, TextWriter stderr, CancellationToken cancellationToken)
    {
        _ = stdout;

        var contextName = ResolveContextName();
        var wrapperFlags = argumentParser.ParseWrapperFlags(args);
        var dockerArgs = wrapperFlags.DockerArgs;

        if (!argumentParser.IsContainerCreateCommand(dockerArgs))
        {
            return await passthroughWorkflow.RunAsync(dockerArgs, contextName, stderr, cancellationToken).ConfigureAwait(false);
        }

        return await createWorkflow.RunAsync(dockerArgs, wrapperFlags, contextName, stderr, cancellationToken).ConfigureAwait(false);
    }

    private string ResolveContextName()
    {
        var contextName = environment.GetEnvironmentVariable("CONTAINAI_DOCKER_CONTEXT");
        if (string.IsNullOrWhiteSpace(contextName))
        {
            contextName = options.DefaultContext;
        }

        return contextName;
    }
}
