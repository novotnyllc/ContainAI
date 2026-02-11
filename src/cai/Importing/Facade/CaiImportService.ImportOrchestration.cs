using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal interface IImportOrchestrationOperations
{
    Task<int> RunImportAsync(ImportCommandOptions options, CancellationToken cancellationToken);
}

internal sealed class CaiImportOrchestrationOperations : IImportOrchestrationOperations
{
    private readonly TextWriter stdout;
    private readonly TextWriter stderr;
    private readonly ImportRunContextResolver runContextResolver;
    private readonly ImportDataVolumeEnsurer dataVolumeEnsurer;
    private readonly ImportManifestLoadingService manifestLoadingService;
    private readonly ImportSourceDispatcher sourceDispatcher;

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
        stdout = standardOutput ?? throw new ArgumentNullException(nameof(standardOutput));
        stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));
        ArgumentNullException.ThrowIfNull(dependencies);
        runContextResolver = dependencies.RunContextResolver;
        dataVolumeEnsurer = dependencies.DataVolumeEnsurer;
        manifestLoadingService = dependencies.ManifestLoadingService;
        sourceDispatcher = dependencies.SourceDispatcher;
    }

    public Task<int> RunImportAsync(ImportCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return RunImportCoreAsync(options, cancellationToken);
    }

    private static string ResolveDockerContextName()
    {
        var explicitContext = Environment.GetEnvironmentVariable("DOCKER_CONTEXT");
        return !string.IsNullOrWhiteSpace(explicitContext)
            ? explicitContext
            : "default";
    }

    private async Task<int> RunImportCoreAsync(ImportCommandOptions options, CancellationToken cancellationToken)
    {
        var runContext = await runContextResolver.ResolveAsync(options, cancellationToken).ConfigureAwait(false);
        if (!runContext.Success)
        {
            await stderr.WriteLineAsync(runContext.Error!).ConfigureAwait(false);
            return 1;
        }

        var context = runContext.Value!;

        await stdout.WriteLineAsync($"Using data volume: {context.Volume}").ConfigureAwait(false);
        if (options.DryRun)
        {
            await stdout.WriteLineAsync($"Dry-run context: {ResolveDockerContextName()}").ConfigureAwait(false);
        }

        var ensureVolumeCode = await dataVolumeEnsurer
            .EnsureVolumeAsync(context.Volume, options.DryRun, cancellationToken)
            .ConfigureAwait(false);
        if (ensureVolumeCode != 0)
        {
            return ensureVolumeCode;
        }

        var manifestLoadResult = manifestLoadingService.LoadManifestEntries();
        if (!manifestLoadResult.Success)
        {
            await stderr.WriteLineAsync(manifestLoadResult.ErrorMessage!).ConfigureAwait(false);
            return 1;
        }

        return await sourceDispatcher
            .DispatchAsync(options, context, manifestLoadResult.Entries!, cancellationToken)
            .ConfigureAwait(false);
    }
}
