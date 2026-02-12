using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed class ImportManifestDispatchCoordinator(
    ImportDataVolumeEnsurer dataVolumeEnsurer,
    ImportManifestLoadingService manifestLoadingService,
    ImportSourceDispatcher sourceDispatcher,
    IImportRunContextReporter contextReporter) : IImportManifestDispatchCoordinator
{
    public async Task<int> ExecuteAsync(
        ImportCommandOptions options,
        ImportRunContext context,
        CancellationToken cancellationToken)
    {
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
            await contextReporter.WriteManifestLoadErrorAsync(manifestLoadResult.ErrorMessage!).ConfigureAwait(false);
            return 1;
        }

        return await sourceDispatcher
            .DispatchAsync(options, context, manifestLoadResult.Entries!, cancellationToken)
            .ConfigureAwait(false);
    }
}
