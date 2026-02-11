using ContainAI.Cli.Host.Importing.Symlinks;

namespace ContainAI.Cli.Host.Importing.Transfer;

internal sealed class ImportManifestTransferOperations : IImportManifestTransferOperations
{
    private readonly IImportPostCopyOperations postCopyOperations;
    private readonly IImportManifestTargetInitializationOperations targetInitializationOperations;
    private readonly IImportManifestEntryTransferPipeline manifestEntryTransferPipeline;

    public ImportManifestTransferOperations(TextWriter standardOutput, TextWriter standardError)
        : this(
            standardOutput,
            standardError,
            new CaiImportPostCopyOperations(standardOutput, standardError),
            new ImportSymlinkRelinker(standardOutput, standardError),
            new ImportManifestTargetInitializer(standardOutput, standardError),
            new ImportManifestPlanBuilder(),
            new ImportManifestCopyOperations(standardOutput, standardError))
    {
    }

    internal ImportManifestTransferOperations(
        TextWriter standardOutput,
        TextWriter standardError,
        IImportPostCopyOperations importPostCopyOperations,
        IImportSymlinkRelinker importSymlinkRelinker,
        IImportManifestTargetInitializer importManifestTargetInitializer,
        IImportManifestPlanBuilder importManifestPlanBuilder,
        IImportManifestCopyOperations importManifestCopyOperations)
        : this(
            standardOutput,
            standardError,
            importPostCopyOperations,
            importManifestTargetInitializer,
            importManifestPlanBuilder,
            importManifestCopyOperations,
            CreatePostCopyTransferOperations(importPostCopyOperations, importSymlinkRelinker))
    {
    }

    internal ImportManifestTransferOperations(
        TextWriter standardOutput,
        TextWriter standardError,
        IImportPostCopyOperations importPostCopyOperations,
        IImportManifestTargetInitializer importManifestTargetInitializer,
        IImportManifestPlanBuilder importManifestPlanBuilder,
        IImportManifestCopyOperations importManifestCopyOperations,
        IImportManifestPostCopyTransferOperations importManifestPostCopyTransferOperations)
        : this(
            importPostCopyOperations,
            CreateTargetInitializationOperations(importManifestTargetInitializer),
            CreateEntryTransferPipeline(
                standardOutput,
                standardError,
                importManifestPlanBuilder,
                importManifestCopyOperations,
                importManifestPostCopyTransferOperations))
    {
    }

    private ImportManifestTransferOperations(
        IImportPostCopyOperations importPostCopyOperations,
        IImportManifestTargetInitializationOperations importManifestTargetInitializationOperations,
        IImportManifestEntryTransferPipeline importManifestEntryTransferPipeline)
        => (postCopyOperations, targetInitializationOperations, manifestEntryTransferPipeline) = (
            importPostCopyOperations ?? throw new ArgumentNullException(nameof(importPostCopyOperations)),
            importManifestTargetInitializationOperations ?? throw new ArgumentNullException(nameof(importManifestTargetInitializationOperations)),
            importManifestEntryTransferPipeline ?? throw new ArgumentNullException(nameof(importManifestEntryTransferPipeline)));

    public async Task<int> InitializeImportTargetsAsync(
        string volume,
        string sourceRoot,
        IReadOnlyList<ManifestEntry> entries,
        bool noSecrets,
        CancellationToken cancellationToken)
        => await targetInitializationOperations.InitializeTargetsAsync(
            volume,
            sourceRoot,
            entries,
            noSecrets,
            cancellationToken).ConfigureAwait(false);

    public async Task<int> ImportManifestEntryAsync(
        string volume,
        string sourceRoot,
        ManifestEntry entry,
        bool excludePriv,
        bool noExcludes,
        bool dryRun,
        bool verbose,
        CancellationToken cancellationToken)
        => await manifestEntryTransferPipeline.ImportAsync(
            volume,
            sourceRoot,
            entry,
            excludePriv,
            noExcludes,
            dryRun,
            verbose,
            cancellationToken).ConfigureAwait(false);

    public Task<int> EnforceSecretPathPermissionsAsync(
        string volume,
        IReadOnlyList<ManifestEntry> manifestEntries,
        bool noSecrets,
        bool verbose,
        CancellationToken cancellationToken)
        => postCopyOperations.EnforceSecretPathPermissionsAsync(volume, manifestEntries, noSecrets, verbose, cancellationToken);

    private static ImportManifestPostCopyTransferOperations CreatePostCopyTransferOperations(
        IImportPostCopyOperations importPostCopyOperations,
        IImportSymlinkRelinker importSymlinkRelinker)
        => new ImportManifestPostCopyTransferOperations(
            importPostCopyOperations ?? throw new ArgumentNullException(nameof(importPostCopyOperations)),
            importSymlinkRelinker ?? throw new ArgumentNullException(nameof(importSymlinkRelinker)));

    private static ImportManifestTargetInitializationOperations CreateTargetInitializationOperations(
        IImportManifestTargetInitializer importManifestTargetInitializer)
        => new(importManifestTargetInitializer ?? throw new ArgumentNullException(nameof(importManifestTargetInitializer)));

    private static ImportManifestEntryTransferPipeline CreateEntryTransferPipeline(
        TextWriter standardOutput,
        TextWriter standardError,
        IImportManifestPlanBuilder importManifestPlanBuilder,
        IImportManifestCopyOperations importManifestCopyOperations,
        IImportManifestPostCopyTransferOperations importManifestPostCopyTransferOperations)
        => new(
            standardOutput ?? throw new ArgumentNullException(nameof(standardOutput)),
            standardError ?? throw new ArgumentNullException(nameof(standardError)),
            importManifestPlanBuilder ?? throw new ArgumentNullException(nameof(importManifestPlanBuilder)),
            importManifestCopyOperations ?? throw new ArgumentNullException(nameof(importManifestCopyOperations)),
            importManifestPostCopyTransferOperations ?? throw new ArgumentNullException(nameof(importManifestPostCopyTransferOperations)));
}
