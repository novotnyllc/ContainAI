using System.Text;

namespace ContainAI.Cli.Host.Importing.Transfer;

internal sealed partial class ImportManifestTargetInitializer
{
    private static string BuildEnsureDirectoryCommand(string targetPath, bool isSecret)
    {
        var escapedTarget = EscapeForSingleQuotedShell(targetPath);
        var command = $"mkdir -p '/mnt/agent-data/{escapedTarget}' && chown -R 1000:1000 '/mnt/agent-data/{escapedTarget}' || true";
        if (isSecret)
        {
            command += $" && chmod 700 '/mnt/agent-data/{escapedTarget}'";
        }

        return command;
    }

    private static string BuildEnsureFileCommand(ManifestEntry entry)
    {
        var ensureFileCommand = new StringBuilder();
        ensureFileCommand.Append($"dest='/mnt/agent-data/{EscapeForSingleQuotedShell(entry.Target)}'; ");
        ensureFileCommand.Append("mkdir -p \"$(dirname \"$dest\")\"; ");
        ensureFileCommand.Append("if [ ! -f \"$dest\" ]; then : > \"$dest\"; fi; ");
        if (entry.Flags.Contains('j', StringComparison.Ordinal))
        {
            ensureFileCommand.Append("if [ ! -s \"$dest\" ]; then printf '{}' > \"$dest\"; fi; ");
        }

        ensureFileCommand.Append("chown 1000:1000 \"$dest\" || true; ");
        if (IsSecretEntry(entry))
        {
            ensureFileCommand.Append("chmod 600 \"$dest\"; ");
        }

        return ensureFileCommand.ToString();
    }
}
