namespace ContainAI.Cli.Host.Importing.Transfer;

internal sealed class ImportManifestTransferDependencies
{
    public ImportManifestTransferDependencies(
        IImportPostCopyOperations postCopyOperations,
        IImportManifestTargetInitializationOperations targetInitializationOperations,
        IImportManifestEntryTransferPipeline manifestEntryTransferPipeline)
    {
        PostCopyOperations = postCopyOperations ?? throw new ArgumentNullException(nameof(postCopyOperations));
        TargetInitializationOperations = targetInitializationOperations ?? throw new ArgumentNullException(nameof(targetInitializationOperations));
        ManifestEntryTransferPipeline = manifestEntryTransferPipeline ?? throw new ArgumentNullException(nameof(manifestEntryTransferPipeline));
    }

    public IImportPostCopyOperations PostCopyOperations { get; }

    public IImportManifestTargetInitializationOperations TargetInitializationOperations { get; }

    public IImportManifestEntryTransferPipeline ManifestEntryTransferPipeline { get; }
}
