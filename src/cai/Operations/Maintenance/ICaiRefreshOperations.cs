namespace ContainAI.Cli.Host;

internal interface ICaiRefreshOperations
{
    Task<int> RunRefreshAsync(bool rebuild, bool showHelp, CancellationToken cancellationToken);
}
