using ContainAI.Cli.Host.Importing.Symlinks;

namespace ContainAI.Cli.Host.Importing.Transfer;

internal sealed partial class ImportManifestTransferOperations : CaiRuntimeSupport
    , IImportManifestTransferOperations
{
    private readonly IImportPostCopyOperations postCopyOperations;
    private readonly IImportManifestTargetInitializer targetInitializer;
    private readonly IImportManifestPlanBuilder planBuilder;
    private readonly IImportManifestCopyOperations copyOperations;
    private readonly IImportManifestPostCopyTransferOperations postCopyTransferOperations;

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
        : base(standardOutput, standardError)
        => (postCopyOperations, targetInitializer, planBuilder, copyOperations, postCopyTransferOperations) = (
            importPostCopyOperations ?? throw new ArgumentNullException(nameof(importPostCopyOperations)),
            importManifestTargetInitializer ?? throw new ArgumentNullException(nameof(importManifestTargetInitializer)),
            importManifestPlanBuilder ?? throw new ArgumentNullException(nameof(importManifestPlanBuilder)),
            importManifestCopyOperations ?? throw new ArgumentNullException(nameof(importManifestCopyOperations)),
            importManifestPostCopyTransferOperations ?? throw new ArgumentNullException(nameof(importManifestPostCopyTransferOperations)));

    private static ImportManifestPostCopyTransferOperations CreatePostCopyTransferOperations(
        IImportPostCopyOperations importPostCopyOperations,
        IImportSymlinkRelinker importSymlinkRelinker)
        => new ImportManifestPostCopyTransferOperations(
            importPostCopyOperations ?? throw new ArgumentNullException(nameof(importPostCopyOperations)),
            importSymlinkRelinker ?? throw new ArgumentNullException(nameof(importSymlinkRelinker)));
}
