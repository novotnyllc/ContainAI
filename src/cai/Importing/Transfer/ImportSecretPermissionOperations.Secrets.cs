using System.Text;

namespace ContainAI.Cli.Host;

internal sealed partial class ImportSecretPermissionOperations
{
    private static (HashSet<string> SecretDirectories, HashSet<string> SecretFiles) CollectSecretPaths(
        IReadOnlyList<ManifestEntry> manifestEntries,
        bool noSecrets)
    {
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

        return (secretDirectories, secretFiles);
    }

    private static string BuildBulkPermissionsCommand(HashSet<string> secretDirectories, HashSet<string> secretFiles)
    {
        var commandBuilder = new StringBuilder();
        foreach (var directory in secretDirectories.OrderBy(static value => value, StringComparer.Ordinal))
        {
            commandBuilder.Append("if [ -d '/target/");
            commandBuilder.Append(EscapeForSingleQuotedShell(directory));
            commandBuilder.Append("' ]; then chmod 700 '/target/");
            commandBuilder.Append(EscapeForSingleQuotedShell(directory));
            commandBuilder.Append("'; chown 1000:1000 '/target/");
            commandBuilder.Append(EscapeForSingleQuotedShell(directory));
            commandBuilder.Append("' || true; fi; ");
        }

        foreach (var file in secretFiles.OrderBy(static value => value, StringComparer.Ordinal))
        {
            commandBuilder.Append("if [ -f '/target/");
            commandBuilder.Append(EscapeForSingleQuotedShell(file));
            commandBuilder.Append("' ]; then chmod 600 '/target/");
            commandBuilder.Append(EscapeForSingleQuotedShell(file));
            commandBuilder.Append("'; chown 1000:1000 '/target/");
            commandBuilder.Append(EscapeForSingleQuotedShell(file));
            commandBuilder.Append("' || true; fi; ");
        }

        return commandBuilder.ToString();
    }

    private static string BuildEntryPermissionsCommand(string normalizedTarget, bool isDirectory)
    {
        var chmodMode = isDirectory ? "700" : "600";
        return $"target='/target/{EscapeForSingleQuotedShell(normalizedTarget)}'; " +
               "if [ -e \"$target\" ]; then chmod " + chmodMode + " \"$target\"; fi; " +
               "if [ -e \"$target\" ]; then chown 1000:1000 \"$target\" || true; fi";
    }
}
