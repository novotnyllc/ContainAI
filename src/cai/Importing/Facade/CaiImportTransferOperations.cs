using ContainAI.Cli.Host.Importing.Transfer;

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

internal sealed class CaiImportTransferOperations : IImportTransferOperations
{
    private readonly IImportArchiveTransferOperations archiveTransferOperations;
    private readonly IImportManifestTransferOperations manifestTransferOperations;
    private readonly IImportOverrideTransferOperations overrideTransferOperations;

    public CaiImportTransferOperations(TextWriter standardOutput, TextWriter standardError)
        : this(
            standardOutput,
            standardError,
            new ImportArchiveTransferOperations(standardOutput, standardError),
            new ImportManifestTransferOperations(standardOutput, standardError),
            new ImportOverrideTransferOperations(standardOutput, standardError))
    {
    }

    internal CaiImportTransferOperations(
        TextWriter standardOutput,
        TextWriter standardError,
        IImportArchiveTransferOperations importArchiveTransferOperations,
        IImportManifestTransferOperations importManifestTransferOperations,
        IImportOverrideTransferOperations importOverrideTransferOperations)
    {
        ArgumentNullException.ThrowIfNull(standardOutput);
        ArgumentNullException.ThrowIfNull(standardError);
        (archiveTransferOperations, manifestTransferOperations, overrideTransferOperations) = (
            importArchiveTransferOperations ?? throw new ArgumentNullException(nameof(importArchiveTransferOperations)),
            importManifestTransferOperations ?? throw new ArgumentNullException(nameof(importManifestTransferOperations)),
            importOverrideTransferOperations ?? throw new ArgumentNullException(nameof(importOverrideTransferOperations)));
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
