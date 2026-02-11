using ContainAI.Cli.Host.Importing.Transfer;

namespace ContainAI.Cli.Host;

internal sealed class CaiImportTransferOperations : IImportTransferOperations
{
    private readonly IImportArchiveTransferOperations archiveTransferOperations;
    private readonly IImportManifestTransferOperations manifestTransferOperations;
    private readonly IImportOverrideTransferOperations overrideTransferOperations;

    public CaiImportTransferOperations(TextWriter standardOutput, TextWriter standardError)
        : this(CaiImportTransferDependenciesFactory.Create(standardOutput, standardError))
    {
    }

    internal CaiImportTransferOperations(CaiImportTransferDependencies dependencies)
    {
        ArgumentNullException.ThrowIfNull(dependencies);
        (archiveTransferOperations, manifestTransferOperations, overrideTransferOperations) = (
            dependencies.ArchiveTransferOperations,
            dependencies.ManifestTransferOperations,
            dependencies.OverrideTransferOperations);
    }

    public Task<int> RestoreArchiveImportAsync(string volume, string archivePath, bool excludePriv, CancellationToken cancellationToken)
        => archiveTransferOperations.RestoreArchiveImportAsync(volume, archivePath, excludePriv, cancellationToken);

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

    public Task<int> ApplyImportOverridesAsync(
        string volume,
        IReadOnlyList<ManifestEntry> manifestEntries,
        bool noSecrets,
        bool dryRun,
        bool verbose,
        CancellationToken cancellationToken)
        => overrideTransferOperations.ApplyImportOverridesAsync(volume, manifestEntries, noSecrets, dryRun, verbose, cancellationToken);
}
