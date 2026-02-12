namespace ContainAI.Cli.Host.Importing.Transfer;

internal interface IImportManifestEntryTransferPipeline
{
    Task<int> ImportAsync(
        string volume,
        string sourceRoot,
        ManifestEntry entry,
        bool excludePriv,
        bool noExcludes,
        bool dryRun,
        bool verbose,
        CancellationToken cancellationToken);
}
