namespace ContainAI.Cli.Host;

internal interface IImportTransferOperations
{
    Task<int> RestoreArchiveImportAsync(string volume, string archivePath, bool excludePriv, CancellationToken cancellationToken);

    Task<int> InitializeImportTargetsAsync(
        string volume,
        string sourceRoot,
        IReadOnlyList<ManifestEntry> entries,
        bool noSecrets,
        CancellationToken cancellationToken);

    Task<int> ImportManifestEntryAsync(
        string volume,
        string sourceRoot,
        ManifestEntry entry,
        bool excludePriv,
        bool noExcludes,
        bool dryRun,
        bool verbose,
        CancellationToken cancellationToken);

    Task<int> EnforceSecretPathPermissionsAsync(
        string volume,
        IReadOnlyList<ManifestEntry> manifestEntries,
        bool noSecrets,
        bool verbose,
        CancellationToken cancellationToken);

    Task<int> ApplyImportOverridesAsync(
        string volume,
        IReadOnlyList<ManifestEntry> manifestEntries,
        bool noSecrets,
        bool dryRun,
        bool verbose,
        CancellationToken cancellationToken);
}
