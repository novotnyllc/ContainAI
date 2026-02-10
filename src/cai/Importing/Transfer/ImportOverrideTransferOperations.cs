namespace ContainAI.Cli.Host.Importing.Transfer;

internal sealed partial class ImportOverrideTransferOperations : CaiRuntimeSupport
    , IImportOverrideTransferOperations
{
    public ImportOverrideTransferOperations(TextWriter standardOutput, TextWriter standardError)
        : base(standardOutput, standardError)
    {
    }
}
