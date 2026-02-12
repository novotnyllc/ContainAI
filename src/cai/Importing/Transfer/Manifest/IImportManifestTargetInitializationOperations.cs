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
