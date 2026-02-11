namespace ContainAI.Cli.Host;

internal interface IImportEnvironmentOperations
{
    Task<int> ImportEnvironmentVariablesAsync(
        string volume,
        string workspace,
        string? explicitConfigPath,
        bool dryRun,
        bool verbose,
        CancellationToken cancellationToken);
}
