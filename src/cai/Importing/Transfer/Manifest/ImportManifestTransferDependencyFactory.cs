using ContainAI.Cli.Host.Importing.Symlinks;

namespace ContainAI.Cli.Host.Importing.Transfer;

internal static class ImportManifestTransferDependencyFactory
{
    public static ImportManifestTransferDependencies Create(TextWriter standardOutput, TextWriter standardError)
    {
        ArgumentNullException.ThrowIfNull(standardOutput);
        ArgumentNullException.ThrowIfNull(standardError);

        var postCopyOperations = new CaiImportPostCopyOperations(standardOutput, standardError);
        var postCopyTransferOperations = new ImportManifestPostCopyTransferOperations(
            postCopyOperations,
            new ImportSymlinkRelinker(standardOutput, standardError));

        var targetInitializationOperations = new ImportManifestTargetInitializationOperations(
            new ImportManifestTargetInitializer(standardOutput, standardError));

        var manifestEntryTransferPipeline = new ImportManifestEntryTransferPipeline(
            standardOutput,
            standardError,
            new ImportManifestPlanBuilder(),
            new ImportManifestCopyOperations(standardOutput, standardError),
            postCopyTransferOperations);

        return new ImportManifestTransferDependencies(
            postCopyOperations,
            targetInitializationOperations,
            manifestEntryTransferPipeline);
    }
}
