namespace ContainAI.Cli.Host.AgentShims;

internal interface IAgentShimCommandLauncher
{
    Task<int> ExecuteAsync(string binaryPath, IReadOnlyList<string> commandArgs, CancellationToken cancellationToken);
}
