using ContainAI.Cli.Host.Importing.Paths;

namespace ContainAI.Cli.Host;

internal sealed partial class CaiImportPathOperations
{
    private readonly string importExcludePrivKey;
    private readonly IImportAdditionalPathCatalog additionalPathCatalog;
    private readonly IImportAdditionalPathTransferOperations additionalPathTransferOperations;

    public CaiImportPathOperations(TextWriter standardOutput, TextWriter standardError)
        : this(
            standardOutput,
            standardError,
            new ImportAdditionalPathCatalog(standardOutput, standardError),
            new ImportAdditionalPathTransferOperations(standardOutput, standardError))
    {
    }

    internal CaiImportPathOperations(
        TextWriter standardOutput,
        TextWriter standardError,
        IImportAdditionalPathCatalog additionalPathCatalog,
        IImportAdditionalPathTransferOperations additionalPathTransferOperations)
        : base(standardOutput, standardError)
        => (importExcludePrivKey, this.additionalPathCatalog, this.additionalPathTransferOperations) = (
            "import.exclude_priv",
            additionalPathCatalog ?? throw new ArgumentNullException(nameof(additionalPathCatalog)),
            additionalPathTransferOperations ?? throw new ArgumentNullException(nameof(additionalPathTransferOperations)));
}
