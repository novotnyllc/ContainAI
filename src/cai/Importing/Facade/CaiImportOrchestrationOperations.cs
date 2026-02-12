using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed class CaiImportOrchestrationOperations : IImportOrchestrationOperations
{
    private readonly ImportRunContextResolver runContextResolver;
    private readonly ImportRunContextReporter runContextReporter;
    private readonly ImportManifestDispatchCoordinator manifestDispatchCoordinator;

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
        : this(
            standardOutput,
            standardError,
            CaiImportOrchestrationDependenciesFactory.Create(
                standardOutput,
                standardError,
                manifestTomlParser,
                importManifestCatalog,
                importPathOperations,
                importTransferOperations,
                importEnvironmentOperations))
    {
    }

    internal CaiImportOrchestrationOperations(
        TextWriter standardOutput,
        TextWriter standardError,
        CaiImportOrchestrationDependencies dependencies)
    {
        var output = standardOutput ?? throw new ArgumentNullException(nameof(standardOutput));
        var error = standardError ?? throw new ArgumentNullException(nameof(standardError));
        ArgumentNullException.ThrowIfNull(dependencies);

        runContextResolver = dependencies.RunContextResolver;
        runContextReporter = new ImportRunContextReporter(output, error);
        manifestDispatchCoordinator = new ImportManifestDispatchCoordinator(
            dependencies.DataVolumeEnsurer,
            dependencies.ManifestLoadingService,
            dependencies.SourceDispatcher,
            runContextReporter);
    }

    public Task<int> RunImportAsync(ImportCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return RunImportCoreAsync(options, cancellationToken);
    }

    private async Task<int> RunImportCoreAsync(ImportCommandOptions options, CancellationToken cancellationToken)
    {
        var runContext = await runContextResolver.ResolveAsync(options, cancellationToken).ConfigureAwait(false);
        if (!runContext.Success)
        {
            await runContextReporter.WriteRunContextErrorAsync(runContext.Error!).ConfigureAwait(false);
            return 1;
        }

        var context = runContext.Value!;
        await runContextReporter.WriteContextAsync(context, options.DryRun).ConfigureAwait(false);
        return await manifestDispatchCoordinator
            .ExecuteAsync(options, context, cancellationToken)
            .ConfigureAwait(false);
    }
}
