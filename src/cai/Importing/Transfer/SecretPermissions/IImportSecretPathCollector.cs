namespace ContainAI.Cli.Host.Importing.Transfer.SecretPermissions;

internal interface IImportSecretPathCollector
{
    SecretPermissionPathCollection Collect(IReadOnlyList<ManifestEntry> manifestEntries, bool noSecrets);
}
