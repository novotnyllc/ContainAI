using ContainAI.Cli.Host;

namespace ContainAI.Cli.Host.Importing.Paths;

internal sealed partial class ImportAdditionalPathTransferOperations : CaiRuntimeSupport
    , IImportAdditionalPathTransferOperations
{
    public ImportAdditionalPathTransferOperations(TextWriter standardOutput, TextWriter standardError)
        : base(standardOutput, standardError)
    {
    }
}
