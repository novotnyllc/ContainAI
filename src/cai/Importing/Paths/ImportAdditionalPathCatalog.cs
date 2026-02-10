using ContainAI.Cli.Host;

namespace ContainAI.Cli.Host.Importing.Paths;

internal sealed partial class ImportAdditionalPathCatalog : CaiRuntimeSupport
    , IImportAdditionalPathCatalog
{
    public ImportAdditionalPathCatalog(TextWriter standardOutput, TextWriter standardError)
        : base(standardOutput, standardError)
    {
    }
}
