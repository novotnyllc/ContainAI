using ContainAI.Cli.Host.DockerProxy.Contracts;
using ContainAI.Cli.Host.DockerProxy.Execution;
using ContainAI.Cli.Host.DockerProxy.Parsing;

namespace ContainAI.Cli.Host.DockerProxy.Workflow;

internal sealed class DockerProxyPassthroughWorkflow : IDockerProxyPassthroughWorkflow
{
    private readonly IDockerProxyArgumentParser argumentParser;
    private readonly IDockerProxyCommandExecutor commandExecutor;
    private readonly IDockerProxyContextSelector contextSelector;

    public DockerProxyPassthroughWorkflow(
        IDockerProxyArgumentParser argumentParser,
        IDockerProxyCommandExecutor commandExecutor,
        IDockerProxyContextSelector contextSelector)
    {
        this.argumentParser = argumentParser;
        this.commandExecutor = commandExecutor;
        this.contextSelector = contextSelector;
    }

    public async Task<int> RunAsync(
        IReadOnlyList<string> dockerArgs,
        string contextName,
        TextWriter stderr,
        CancellationToken cancellationToken)
    {
        var useContainAiContext = await contextSelector
            .ShouldUseContainAiContextAsync(dockerArgs, contextName, cancellationToken)
            .ConfigureAwait(false);

        return await commandExecutor.RunInteractiveAsync(
            useContainAiContext ? argumentParser.PrependContext(contextName, dockerArgs) : dockerArgs,
            stderr,
            cancellationToken).ConfigureAwait(false);
    }
}
