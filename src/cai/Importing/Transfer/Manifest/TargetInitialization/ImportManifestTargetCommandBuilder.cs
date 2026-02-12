using System.Text;
using ContainAI.Cli.Host.RuntimeSupport.Paths;

namespace ContainAI.Cli.Host.Importing.Transfer;

internal sealed class ImportManifestTargetCommandBuilder : IImportManifestTargetCommandBuilder
{
    public string BuildEnsureDirectoryCommand(string targetPath, bool isSecret)
    {
        var escapedTarget = CaiRuntimePathHelpers.EscapeForSingleQuotedShell(targetPath);
        var command = $"mkdir -p '/mnt/agent-data/{escapedTarget}' && chown -R 1000:1000 '/mnt/agent-data/{escapedTarget}' || true";
        if (isSecret)
        {
            command += $" && chmod 700 '/mnt/agent-data/{escapedTarget}'";
        }

        return command;
    }

    public string BuildEnsureFileCommand(ManifestEntry entry)
    {
        var ensureFileCommand = new StringBuilder();
        ensureFileCommand.Append($"dest='/mnt/agent-data/{CaiRuntimePathHelpers.EscapeForSingleQuotedShell(entry.Target)}'; ");
        ensureFileCommand.Append("mkdir -p \"$(dirname \"$dest\")\"; ");
        ensureFileCommand.Append("if [ ! -f \"$dest\" ]; then : > \"$dest\"; fi; ");
        if (entry.Flags.Contains('j', StringComparison.Ordinal))
        {
            ensureFileCommand.Append("if [ ! -s \"$dest\" ]; then printf '{}' > \"$dest\"; fi; ");
        }

        ensureFileCommand.Append("chown 1000:1000 \"$dest\" || true; ");
        if (ImportManifestTargetSkipPolicy.IsSecretEntry(entry))
        {
            ensureFileCommand.Append("chmod 600 \"$dest\"; ");
        }

        return ensureFileCommand.ToString();
    }
}
