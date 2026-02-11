namespace ContainAI.Cli.Host.Importing.Transfer.SecretPermissions;

internal readonly record struct SecretPermissionPathCollection(
    HashSet<string> SecretDirectories,
    HashSet<string> SecretFiles)
{
    public bool IsEmpty => SecretDirectories.Count == 0 && SecretFiles.Count == 0;
}
