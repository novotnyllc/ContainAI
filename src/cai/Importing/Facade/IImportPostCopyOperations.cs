namespace ContainAI.Cli.Host;

internal interface IImportPostCopyOperations
{
    Task<int> EnforceSecretPathPermissionsAsync(
        string volume,
        IReadOnlyList<ManifestEntry> manifestEntries,
        bool noSecrets,
        bool verbose,
        CancellationToken cancellationToken);

    Task<int> ApplyManifestPostCopyRulesAsync(
        string volume,
        ManifestEntry entry,
        bool dryRun,
        bool verbose,
        CancellationToken cancellationToken);
}
