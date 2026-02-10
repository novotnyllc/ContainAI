using ContainAI.Cli.Host;

namespace ContainAI.Cli.Host.Importing.Paths;

internal interface IImportAdditionalPathTransferOperations
{
    Task<int> ImportAdditionalPathAsync(
        string volume,
        ImportAdditionalPath additionalPath,
        bool noExcludes,
        bool dryRun,
        bool verbose,
        CancellationToken cancellationToken);
}
