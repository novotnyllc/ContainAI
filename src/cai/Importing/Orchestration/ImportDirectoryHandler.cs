using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed partial class ImportDirectoryHandler : CaiRuntimeSupport
{
    private readonly IImportPathOperations pathOperations;
    private readonly IImportTransferOperations transferOperations;
    private readonly IImportEnvironmentOperations environmentOperations;

    public ImportDirectoryHandler(
        TextWriter standardOutput,
        TextWriter standardError,
        IImportPathOperations pathOperations,
        IImportTransferOperations transferOperations,
        IImportEnvironmentOperations environmentOperations)
        : base(standardOutput, standardError)
    {
        this.pathOperations = pathOperations ?? throw new ArgumentNullException(nameof(pathOperations));
        this.transferOperations = transferOperations ?? throw new ArgumentNullException(nameof(transferOperations));
        this.environmentOperations = environmentOperations ?? throw new ArgumentNullException(nameof(environmentOperations));
    }
}
