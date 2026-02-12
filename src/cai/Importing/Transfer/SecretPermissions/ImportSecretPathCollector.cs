namespace ContainAI.Cli.Host.Importing.Transfer.SecretPermissions;

internal sealed class ImportSecretPathCollector : IImportSecretPathCollector
{
    public SecretPermissionPathCollection Collect(IReadOnlyList<ManifestEntry> manifestEntries, bool noSecrets)
    {
        ArgumentNullException.ThrowIfNull(manifestEntries);

        var secretDirectories = new HashSet<string>(StringComparer.Ordinal);
        var secretFiles = new HashSet<string>(StringComparer.Ordinal);

        foreach (var entry in manifestEntries)
        {
            if (!entry.Flags.Contains('s', StringComparison.Ordinal) || noSecrets)
            {
                continue;
            }

            var normalizedTarget = entry.Target.Replace("\\", "/", StringComparison.Ordinal).TrimStart('/');
            if (entry.Flags.Contains('d', StringComparison.Ordinal))
            {
                secretDirectories.Add(normalizedTarget);
                continue;
            }

            secretFiles.Add(normalizedTarget);
            var parent = Path.GetDirectoryName(normalizedTarget)?.Replace("\\", "/", StringComparison.Ordinal);
            if (!string.IsNullOrWhiteSpace(parent))
            {
                secretDirectories.Add(parent);
            }
        }

        return new SecretPermissionPathCollection(secretDirectories, secretFiles);
    }
}
