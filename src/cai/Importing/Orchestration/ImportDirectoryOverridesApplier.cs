using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed class ImportDirectoryOverridesApplier
{
    private readonly IImportTransferOperations transferOperations;

    public ImportDirectoryOverridesApplier(IImportTransferOperations importTransferOperations)
        => transferOperations = importTransferOperations ?? throw new ArgumentNullException(nameof(importTransferOperations));

    public Task<int> ApplyAsync(
        ImportCommandOptions options,
        string volume,
        ManifestEntry[] manifestEntries,
        CancellationToken cancellationToken)
        => transferOperations.ApplyImportOverridesAsync(
            volume,
            manifestEntries,
            options.NoSecrets,
            options.DryRun,
            options.Verbose,
            cancellationToken);
}
