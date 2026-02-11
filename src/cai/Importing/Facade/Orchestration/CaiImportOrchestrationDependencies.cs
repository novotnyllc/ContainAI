namespace ContainAI.Cli.Host;

internal sealed class CaiImportOrchestrationDependencies
{
    public CaiImportOrchestrationDependencies(
        ImportRunContextResolver runContextResolver,
        ImportDataVolumeEnsurer dataVolumeEnsurer,
        ImportManifestLoadingService manifestLoadingService,
        ImportSourceDispatcher sourceDispatcher)
    {
        RunContextResolver = runContextResolver ?? throw new ArgumentNullException(nameof(runContextResolver));
        DataVolumeEnsurer = dataVolumeEnsurer ?? throw new ArgumentNullException(nameof(dataVolumeEnsurer));
        ManifestLoadingService = manifestLoadingService ?? throw new ArgumentNullException(nameof(manifestLoadingService));
        SourceDispatcher = sourceDispatcher ?? throw new ArgumentNullException(nameof(sourceDispatcher));
    }

    public ImportRunContextResolver RunContextResolver { get; }

    public ImportDataVolumeEnsurer DataVolumeEnsurer { get; }

    public ImportManifestLoadingService ManifestLoadingService { get; }

    public ImportSourceDispatcher SourceDispatcher { get; }
}
