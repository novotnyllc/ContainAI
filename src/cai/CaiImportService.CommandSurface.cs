using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed partial class CaiImportService : CaiRuntimeSupport
{
    private readonly IImportOrchestrationOperations orchestrationOperations;

    public CaiImportService(TextWriter standardOutput, TextWriter standardError)
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

    internal CaiImportService(
        TextWriter standardOutput,
        TextWriter standardError,
        IManifestTomlParser manifestTomlParser)
        : this(
            standardOutput,
            standardError,
            manifestTomlParser,
            new CaiImportManifestCatalog(),
            new CaiImportPathOperations(standardOutput, standardError),
            new CaiImportTransferOperations(standardOutput, standardError),
            new CaiImportEnvironmentOperations(standardOutput, standardError))
    {
    }

    internal CaiImportService(
        TextWriter standardOutput,
        TextWriter standardError,
        IManifestTomlParser manifestTomlParser,
        IImportManifestCatalog importManifestCatalog,
        IImportPathOperations importPathOperations,
        IImportTransferOperations importTransferOperations,
        IImportEnvironmentOperations importEnvironmentOperations)
        : this(
            standardOutput,
            standardError,
            new CaiImportOrchestrationOperations(
                standardOutput,
                standardError,
                manifestTomlParser,
                importManifestCatalog,
                importPathOperations,
                importTransferOperations,
                importEnvironmentOperations))
    {
    }

    internal CaiImportService(
        TextWriter standardOutput,
        TextWriter standardError,
        IImportOrchestrationOperations importOrchestrationOperations)
        : base(standardOutput, standardError)
        => orchestrationOperations = importOrchestrationOperations ?? throw new ArgumentNullException(nameof(importOrchestrationOperations));

    public Task<int> RunImportAsync(ImportCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return orchestrationOperations.RunImportAsync(options, cancellationToken);
    }
}
