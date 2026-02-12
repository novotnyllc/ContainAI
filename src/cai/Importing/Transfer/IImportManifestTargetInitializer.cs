namespace ContainAI.Cli.Host.Importing.Transfer;

internal interface IImportManifestTargetInitializer
{
    Task<int> EnsureEntryTargetAsync(
        string volume,
        string sourceRoot,
        ManifestEntry entry,
        bool noSecrets,
        CancellationToken cancellationToken);
}
