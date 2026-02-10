namespace ContainAI.Cli.Host.Importing.Transfer;

internal interface IImportOverrideTransferOperations
{
    Task<int> ApplyImportOverridesAsync(
        string volume,
        IReadOnlyList<ManifestEntry> manifestEntries,
        bool noSecrets,
        bool dryRun,
        bool verbose,
        CancellationToken cancellationToken);
}
