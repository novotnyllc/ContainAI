using ContainAI.Cli.Host.Importing.Transfer;

namespace ContainAI.Cli.Host;

internal sealed class CaiImportTransferDependencies
{
    public CaiImportTransferDependencies(
        IImportArchiveTransferOperations archiveTransferOperations,
        IImportManifestTransferOperations manifestTransferOperations,
        IImportOverrideTransferOperations overrideTransferOperations)
    {
        ArchiveTransferOperations = archiveTransferOperations ?? throw new ArgumentNullException(nameof(archiveTransferOperations));
        ManifestTransferOperations = manifestTransferOperations ?? throw new ArgumentNullException(nameof(manifestTransferOperations));
        OverrideTransferOperations = overrideTransferOperations ?? throw new ArgumentNullException(nameof(overrideTransferOperations));
    }

    public IImportArchiveTransferOperations ArchiveTransferOperations { get; }

    public IImportManifestTransferOperations ManifestTransferOperations { get; }

    public IImportOverrideTransferOperations OverrideTransferOperations { get; }
}
