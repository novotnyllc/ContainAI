namespace ContainAI.Cli.Host;

internal interface IImportSecretPermissionOperations
{
    Task<int> EnforceSecretPathPermissionsAsync(
        string volume,
        IReadOnlyList<ManifestEntry> manifestEntries,
        bool noSecrets,
        bool verbose,
        CancellationToken cancellationToken);

    Task<int> ApplyEntrySecretPermissionsAsync(
        string volume,
        string normalizedTarget,
        bool isDirectory,
        CancellationToken cancellationToken);
}

internal sealed partial class ImportSecretPermissionOperations : CaiRuntimeSupport
    , IImportSecretPermissionOperations
{
    public ImportSecretPermissionOperations(TextWriter standardOutput, TextWriter standardError)
        : base(standardOutput, standardError)
    {
    }
}
