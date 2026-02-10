namespace ContainAI.Cli.Host.AgentShims;

internal interface IAgentShimDispatcher
{
    Task<int?> TryRunAsync(string invocationName, IReadOnlyList<string> args, CancellationToken cancellationToken);
}
