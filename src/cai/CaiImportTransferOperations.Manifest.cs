using ContainAI.Cli.Host.Importing.Transfer;

namespace ContainAI.Cli.Host;

internal sealed partial class CaiImportTransferOperations
{
    public Task<int> InitializeImportTargetsAsync(
        string volume,
        string sourceRoot,
        IReadOnlyList<ManifestEntry> entries,
        bool noSecrets,
        CancellationToken cancellationToken)
        => manifestTransferOperations.InitializeImportTargetsAsync(volume, sourceRoot, entries, noSecrets, cancellationToken);

    public Task<int> ImportManifestEntryAsync(
        string volume,
        string sourceRoot,
        ManifestEntry entry,
        bool excludePriv,
        bool noExcludes,
        bool dryRun,
        bool verbose,
        CancellationToken cancellationToken)
        => manifestTransferOperations.ImportManifestEntryAsync(
            volume,
            sourceRoot,
            entry,
            excludePriv,
            noExcludes,
            dryRun,
            verbose,
            cancellationToken);

    public Task<int> EnforceSecretPathPermissionsAsync(
        string volume,
        IReadOnlyList<ManifestEntry> manifestEntries,
        bool noSecrets,
        bool verbose,
        CancellationToken cancellationToken)
        => manifestTransferOperations.EnforceSecretPathPermissionsAsync(volume, manifestEntries, noSecrets, verbose, cancellationToken);
}
