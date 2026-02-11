using ContainAI.Cli.Host.Importing.Transfer;

namespace ContainAI.Cli.Host;

internal sealed partial class CaiImportTransferOperations
{
    public Task<int> ApplyImportOverridesAsync(
        string volume,
        IReadOnlyList<ManifestEntry> manifestEntries,
        bool noSecrets,
        bool dryRun,
        bool verbose,
        CancellationToken cancellationToken)
        => overrideTransferOperations.ApplyImportOverridesAsync(volume, manifestEntries, noSecrets, dryRun, verbose, cancellationToken);
}
