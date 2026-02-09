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

internal sealed partial class CaiImportTransferOperations : CaiRuntimeSupport
    , IImportTransferOperations
{
    private readonly IImportPostCopyOperations postCopyOperations;
    private readonly IImportSymlinkRelinker symlinkRelinker;

    public CaiImportTransferOperations(TextWriter standardOutput, TextWriter standardError)
        : this(
            standardOutput,
            standardError,
            new CaiImportPostCopyOperations(standardOutput, standardError),
            new CaiImportSymlinkRelinker(standardOutput, standardError))
    {
    }

    internal CaiImportTransferOperations(
        TextWriter standardOutput,
        TextWriter standardError,
        IImportPostCopyOperations importPostCopyOperations,
        IImportSymlinkRelinker importSymlinkRelinker)
        : base(standardOutput, standardError)
    {
        postCopyOperations = importPostCopyOperations;
        symlinkRelinker = importSymlinkRelinker;
    }

    public Task<int> RestoreArchiveImportAsync(string volume, string archivePath, bool excludePriv, CancellationToken cancellationToken)
        => RestoreArchiveImportCoreAsync(volume, archivePath, excludePriv, cancellationToken);

    public Task<int> InitializeImportTargetsAsync(
        string volume,
        string sourceRoot,
        IReadOnlyList<ManifestEntry> entries,
        bool noSecrets,
        CancellationToken cancellationToken)
        => InitializeImportTargetsCoreAsync(volume, sourceRoot, entries, noSecrets, cancellationToken);

    public Task<int> ImportManifestEntryAsync(
        string volume,
        string sourceRoot,
        ManifestEntry entry,
        bool excludePriv,
        bool noExcludes,
        bool dryRun,
        bool verbose,
        CancellationToken cancellationToken)
        => ImportManifestEntryCoreAsync(
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
        => postCopyOperations.EnforceSecretPathPermissionsAsync(volume, manifestEntries, noSecrets, verbose, cancellationToken);

    public Task<int> ApplyImportOverridesAsync(
        string volume,
        IReadOnlyList<ManifestEntry> manifestEntries,
        bool noSecrets,
        bool dryRun,
        bool verbose,
        CancellationToken cancellationToken)
        => ApplyImportOverridesCoreAsync(volume, manifestEntries, noSecrets, dryRun, verbose, cancellationToken);
}
