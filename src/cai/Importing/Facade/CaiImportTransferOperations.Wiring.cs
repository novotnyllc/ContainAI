using ContainAI.Cli.Host.Importing.Transfer;

namespace ContainAI.Cli.Host;

internal sealed partial class CaiImportTransferOperations
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
        : base(standardOutput, standardError)
        => (archiveTransferOperations, manifestTransferOperations, overrideTransferOperations) = (
            importArchiveTransferOperations ?? throw new ArgumentNullException(nameof(importArchiveTransferOperations)),
            importManifestTransferOperations ?? throw new ArgumentNullException(nameof(importManifestTransferOperations)),
            importOverrideTransferOperations ?? throw new ArgumentNullException(nameof(importOverrideTransferOperations)));
}
