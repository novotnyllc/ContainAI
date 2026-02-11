namespace ContainAI.Cli.Host;

internal interface IImportManifestLoadingService
{
    ImportManifestLoadResult LoadManifestEntries();
}

internal sealed class ImportManifestLoadingService : IImportManifestLoadingService
{
    private readonly ImportManifestEntryLoader manifestEntryLoader;

    public ImportManifestLoadingService(ImportManifestEntryLoader importManifestEntryLoader)
        => manifestEntryLoader = importManifestEntryLoader ?? throw new ArgumentNullException(nameof(importManifestEntryLoader));

    public ImportManifestLoadResult LoadManifestEntries()
    {
        try
        {
            var entries = manifestEntryLoader.LoadManifestEntries();
            return ImportManifestLoadResult.SuccessResult(entries);
        }
        catch (InvalidOperationException ex)
        {
            return ImportManifestLoadResult.FailureResult($"Failed to load import manifests: {ex.Message}");
        }
        catch (IOException ex)
        {
            return ImportManifestLoadResult.FailureResult($"Failed to load import manifests: {ex.Message}");
        }
        catch (UnauthorizedAccessException ex)
        {
            return ImportManifestLoadResult.FailureResult($"Failed to load import manifests: {ex.Message}");
        }
    }
}
