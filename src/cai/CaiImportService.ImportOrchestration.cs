using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal interface IImportOrchestrationOperations
{
    Task<int> RunImportAsync(ImportCommandOptions options, CancellationToken cancellationToken);
}

internal sealed class CaiImportOrchestrationOperations : CaiRuntimeSupport
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

        if (!options.DryRun)
        {
            var ensureVolume = await DockerCaptureAsync(["volume", "create", context.Volume], cancellationToken).ConfigureAwait(false);
            if (ensureVolume.ExitCode != 0)
            {
                await stderr.WriteLineAsync(ensureVolume.StandardError.Trim()).ConfigureAwait(false);
                return 1;
            }
        }

        ManifestEntry[] manifestEntries;
        try
        {
            manifestEntries = manifestEntryLoader.LoadManifestEntries();
        }
        catch (InvalidOperationException ex)
        {
            await stderr.WriteLineAsync($"Failed to load import manifests: {ex.Message}").ConfigureAwait(false);
            return 1;
        }
        catch (IOException ex)
        {
            await stderr.WriteLineAsync($"Failed to load import manifests: {ex.Message}").ConfigureAwait(false);
            return 1;
        }
        catch (UnauthorizedAccessException ex)
        {
            await stderr.WriteLineAsync($"Failed to load import manifests: {ex.Message}").ConfigureAwait(false);
            return 1;
        }

        return File.Exists(context.SourcePath)
            ? await archiveHandler.HandleArchiveImportAsync(options, context.SourcePath, context.Volume, context.ExcludePriv, manifestEntries, cancellationToken).ConfigureAwait(false)
            : await directoryHandler.HandleDirectoryImportAsync(
                options,
                context.Workspace,
                context.ExplicitConfigPath,
                context.SourcePath,
                context.Volume,
                context.ExcludePriv,
                manifestEntries,
                cancellationToken).ConfigureAwait(false);
    }

    private static string ResolveDockerContextName()
    {
        var explicitContext = Environment.GetEnvironmentVariable("DOCKER_CONTEXT");
        if (!string.IsNullOrWhiteSpace(explicitContext))
        {
            return explicitContext;
        }

        return "default";
    }
}
