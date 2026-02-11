namespace ContainAI.Cli.Host;

internal static class CaiImportOrchestrationDependenciesFactory
{
    public static CaiImportOrchestrationDependencies Create(
        TextWriter standardOutput,
        TextWriter standardError,
        IManifestTomlParser manifestTomlParser,
        IImportManifestCatalog importManifestCatalog,
        IImportPathOperations importPathOperations,
        IImportTransferOperations importTransferOperations,
        IImportEnvironmentOperations importEnvironmentOperations)
    {
        ArgumentNullException.ThrowIfNull(standardOutput);
        ArgumentNullException.ThrowIfNull(standardError);
        ArgumentNullException.ThrowIfNull(manifestTomlParser);
        ArgumentNullException.ThrowIfNull(importManifestCatalog);
        ArgumentNullException.ThrowIfNull(importPathOperations);
        ArgumentNullException.ThrowIfNull(importTransferOperations);
        ArgumentNullException.ThrowIfNull(importEnvironmentOperations);

        var runContextResolver = new ImportRunContextResolver(standardOutput, standardError, importPathOperations);
        var manifestEntryLoader = new ImportManifestEntryLoader(manifestTomlParser, importManifestCatalog);
        var dataVolumeEnsurer = new ImportDataVolumeEnsurer(standardError);
        var manifestLoadingService = new ImportManifestLoadingService(manifestEntryLoader);

        var archiveHandler = new ImportArchiveHandler(standardOutput, standardError, importTransferOperations);
        var directoryHandler = new ImportDirectoryHandler(
            standardOutput,
            standardError,
            importPathOperations,
            importTransferOperations,
            importEnvironmentOperations);
        var sourceDispatcher = new ImportSourceDispatcher(archiveHandler, directoryHandler);

        return new CaiImportOrchestrationDependencies(
            runContextResolver,
            dataVolumeEnsurer,
            manifestLoadingService,
            sourceDispatcher);
    }
}
