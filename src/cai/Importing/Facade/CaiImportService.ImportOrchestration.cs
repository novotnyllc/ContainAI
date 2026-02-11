using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal interface IImportOrchestrationOperations
{
    Task<int> RunImportAsync(ImportCommandOptions options, CancellationToken cancellationToken);
}

internal sealed partial class CaiImportOrchestrationOperations : CaiRuntimeSupport
    , IImportOrchestrationOperations
{
    private readonly ImportRunContextResolver runContextResolver;
    private readonly ImportManifestEntryLoader manifestEntryLoader;
    private readonly ImportArchiveHandler archiveHandler;
    private readonly ImportDirectoryHandler directoryHandler;

    public CaiImportOrchestrationOperations(TextWriter standardOutput, TextWriter standardError)
        : this(
            standardOutput,
            standardError,
            new ManifestTomlParser(),
            new CaiImportManifestCatalog(),
            new CaiImportPathOperations(standardOutput, standardError),
            new CaiImportTransferOperations(standardOutput, standardError),
            new CaiImportEnvironmentOperations(standardOutput, standardError))
    {
    }

    internal CaiImportOrchestrationOperations(
        TextWriter standardOutput,
        TextWriter standardError,
        IManifestTomlParser manifestTomlParser,
        IImportManifestCatalog importManifestCatalog,
        IImportPathOperations importPathOperations,
        IImportTransferOperations importTransferOperations,
        IImportEnvironmentOperations importEnvironmentOperations)
        : base(standardOutput, standardError)
    {
        ArgumentNullException.ThrowIfNull(manifestTomlParser);
        ArgumentNullException.ThrowIfNull(importManifestCatalog);
        var pathOperations = importPathOperations ?? throw new ArgumentNullException(nameof(importPathOperations));
        ArgumentNullException.ThrowIfNull(importTransferOperations);
        ArgumentNullException.ThrowIfNull(importEnvironmentOperations);
        runContextResolver = new ImportRunContextResolver(standardOutput, standardError, pathOperations);
        manifestEntryLoader = new ImportManifestEntryLoader(manifestTomlParser, importManifestCatalog);
        archiveHandler = new ImportArchiveHandler(standardOutput, standardError, importTransferOperations);
        directoryHandler = new ImportDirectoryHandler(
            standardOutput,
            standardError,
            pathOperations,
            importTransferOperations,
            importEnvironmentOperations);
    }

    public Task<int> RunImportAsync(ImportCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return RunImportCoreAsync(options, cancellationToken);
    }
}
