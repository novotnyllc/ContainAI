namespace ContainAI.Cli.Host.DockerProxy.Execution;

internal interface IDockerProxyContextSelector
{
    Task<bool> ShouldUseContainAiContextAsync(IReadOnlyList<string> args, string contextName, CancellationToken cancellationToken);
}
