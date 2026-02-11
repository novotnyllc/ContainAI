namespace ContainAI.Cli.Host.Importing.Transfer;

internal interface IImportManifestTargetInitializationOperations
{
    Task<int> InitializeTargetsAsync(
        string volume,
        string sourceRoot,
        IReadOnlyList<ManifestEntry> entries,
        bool noSecrets,
        CancellationToken cancellationToken);
}

internal sealed class ImportManifestTargetInitializationOperations : IImportManifestTargetInitializationOperations
{
    private readonly IImportManifestTargetInitializer targetInitializer;

    public ImportManifestTargetInitializationOperations(IImportManifestTargetInitializer importManifestTargetInitializer)
        => targetInitializer = importManifestTargetInitializer ?? throw new ArgumentNullException(nameof(importManifestTargetInitializer));

    public async Task<int> InitializeTargetsAsync(
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
