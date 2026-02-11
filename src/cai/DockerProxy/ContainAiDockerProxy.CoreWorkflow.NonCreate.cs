namespace ContainAI.Cli.Host;

internal sealed partial class ContainAiDockerProxyService
{
    private async Task<int> RunNonCreateAsync(
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
