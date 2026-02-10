namespace ContainAI.Cli.Host.Importing.Transfer;

internal sealed partial class ImportManifestTransferOperations
{
    public async Task<int> InitializeImportTargetsAsync(
        string volume,
        string sourceRoot,
        IReadOnlyList<ManifestEntry> entries,
        bool noSecrets,
        CancellationToken cancellationToken)
    {
        foreach (var entry in entries)
        {
            var ensureCode = await targetInitializer.EnsureEntryTargetAsync(
                volume,
                sourceRoot,
                entry,
                noSecrets,
                cancellationToken).ConfigureAwait(false);
            if (ensureCode != 0)
            {
                return ensureCode;
            }
        }

        return 0;
    }
}
