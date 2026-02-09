using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed partial class CaiImportService : CaiRuntimeSupport
{
    private readonly IImportManifestCatalog manifestCatalog;
    private readonly IImportPathOperations pathOperations;
    private readonly IImportTransferOperations transferOperations;

    public CaiImportService(TextWriter standardOutput, TextWriter standardError)
        : this(
            standardOutput,
            standardError,
            new CaiImportManifestCatalog(),
            new CaiImportPathOperations(standardOutput, standardError),
            new CaiImportTransferOperations(standardOutput, standardError))
    {
    }

    internal CaiImportService(
        TextWriter standardOutput,
        TextWriter standardError,
        IImportManifestCatalog importManifestCatalog,
        IImportPathOperations importPathOperations,
        IImportTransferOperations importTransferOperations)
        : base(standardOutput, standardError)
    {
        manifestCatalog = importManifestCatalog;
        pathOperations = importPathOperations;
        transferOperations = importTransferOperations;
    }

    public Task<int> RunImportAsync(ImportCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        var parsed = new ParsedImportOptions(
            SourcePath: options.From,
            ExplicitVolume: options.DataVolume,
            Workspace: options.Workspace,
            ConfigPath: options.Config,
            DryRun: options.DryRun,
            NoExcludes: options.NoExcludes,
            NoSecrets: options.NoSecrets,
            Verbose: options.Verbose,
            Error: null);
        return RunImportCoreAsync(parsed, cancellationToken);
    }
}
