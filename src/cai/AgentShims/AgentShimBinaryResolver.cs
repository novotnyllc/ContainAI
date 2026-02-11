namespace ContainAI.Cli.Host.AgentShims;

internal sealed class AgentShimBinaryResolver : IAgentShimBinaryResolver
{
    private readonly IAgentShimCurrentExecutableResolver currentExecutableResolver;
    private readonly IAgentShimDirectoryResolver directoryResolver;
    private readonly IAgentShimBinaryPathResolver binaryPathResolver;

    public AgentShimBinaryResolver()
        : this(
            new AgentShimCurrentExecutableResolver(),
            new AgentShimDirectoryResolver(),
            new AgentShimBinaryPathResolver(new AgentShimPathCandidateFilter()))
    {
    }

    internal AgentShimBinaryResolver(
        IAgentShimCurrentExecutableResolver agentShimCurrentExecutableResolver,
        IAgentShimDirectoryResolver agentShimDirectoryResolver,
        IAgentShimBinaryPathResolver agentShimBinaryPathResolver)
    {
        currentExecutableResolver = agentShimCurrentExecutableResolver ?? throw new ArgumentNullException(nameof(agentShimCurrentExecutableResolver));
        directoryResolver = agentShimDirectoryResolver ?? throw new ArgumentNullException(nameof(agentShimDirectoryResolver));
        binaryPathResolver = agentShimBinaryPathResolver ?? throw new ArgumentNullException(nameof(agentShimBinaryPathResolver));
    }

    public string ResolveCurrentExecutablePath()
        => currentExecutableResolver.Resolve();

    public string[] ResolveShimDirectories()
        => directoryResolver.ResolveDirectories();

    public string? ResolveBinaryPath(string binary, IReadOnlyList<string> shimDirectories, string currentExecutablePath)
        => binaryPathResolver.Resolve(binary, shimDirectories, currentExecutablePath);
}
