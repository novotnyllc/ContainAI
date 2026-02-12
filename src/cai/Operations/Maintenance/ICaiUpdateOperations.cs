namespace ContainAI.Cli.Host;

internal interface ICaiUpdateOperations
{
    Task<int> RunUpdateAsync(
        bool dryRun,
        bool stopContainers,
        bool limaRecreate,
        bool showHelp,
        CancellationToken cancellationToken);
}
