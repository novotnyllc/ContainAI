using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed class ImportDirectoryTargetInitializer
{
    private readonly IImportTransferOperations transferOperations;

    public ImportDirectoryTargetInitializer(IImportTransferOperations importTransferOperations)
        => transferOperations = importTransferOperations ?? throw new ArgumentNullException(nameof(importTransferOperations));

    public async Task<int> InitializeIfNeededAsync(
        ImportCommandOptions options,
        string volume,
        string sourcePath,
        ManifestEntry[] manifestEntries,
        CancellationToken cancellationToken)
    {
        if (options.DryRun)
        {
            return 0;
        }

        return await transferOperations.InitializeImportTargetsAsync(
            volume,
            sourcePath,
            manifestEntries,
            options.NoSecrets,
            cancellationToken).ConfigureAwait(false);
    }
}
