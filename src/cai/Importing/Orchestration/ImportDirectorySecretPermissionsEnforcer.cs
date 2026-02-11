using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed class ImportDirectorySecretPermissionsEnforcer
{
    private readonly IImportTransferOperations transferOperations;

    public ImportDirectorySecretPermissionsEnforcer(IImportTransferOperations importTransferOperations)
        => transferOperations = importTransferOperations ?? throw new ArgumentNullException(nameof(importTransferOperations));

    public async Task<int> EnforceIfNeededAsync(
        ImportCommandOptions options,
        string volume,
        ManifestEntry[] manifestEntries,
        CancellationToken cancellationToken)
    {
        if (options.DryRun)
        {
            return 0;
        }

        return await transferOperations.EnforceSecretPathPermissionsAsync(
            volume,
            manifestEntries,
            options.NoSecrets,
            options.Verbose,
            cancellationToken).ConfigureAwait(false);
    }
}
