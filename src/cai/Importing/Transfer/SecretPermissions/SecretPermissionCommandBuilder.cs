using System.Text;
using ContainAI.Cli.Host.RuntimeSupport.Paths;

namespace ContainAI.Cli.Host.Importing.Transfer.SecretPermissions;

internal sealed class SecretPermissionCommandBuilder : ISecretPermissionCommandBuilder
{
    public string BuildBulkPermissionsCommand(IReadOnlyCollection<string> secretDirectories, IReadOnlyCollection<string> secretFiles)
    {
        ArgumentNullException.ThrowIfNull(secretDirectories);
        ArgumentNullException.ThrowIfNull(secretFiles);

        var commandBuilder = new StringBuilder();

        foreach (var directory in secretDirectories.OrderBy(static value => value, StringComparer.Ordinal))
        {
            commandBuilder.Append("if [ -d '/target/");
            commandBuilder.Append(CaiRuntimePathHelpers.EscapeForSingleQuotedShell(directory));
            commandBuilder.Append("' ]; then chmod 700 '/target/");
            commandBuilder.Append(CaiRuntimePathHelpers.EscapeForSingleQuotedShell(directory));
            commandBuilder.Append("'; chown 1000:1000 '/target/");
            commandBuilder.Append(CaiRuntimePathHelpers.EscapeForSingleQuotedShell(directory));
            commandBuilder.Append("' || true; fi; ");
        }

        foreach (var file in secretFiles.OrderBy(static value => value, StringComparer.Ordinal))
        {
            commandBuilder.Append("if [ -f '/target/");
            commandBuilder.Append(CaiRuntimePathHelpers.EscapeForSingleQuotedShell(file));
            commandBuilder.Append("' ]; then chmod 600 '/target/");
            commandBuilder.Append(CaiRuntimePathHelpers.EscapeForSingleQuotedShell(file));
            commandBuilder.Append("'; chown 1000:1000 '/target/");
            commandBuilder.Append(CaiRuntimePathHelpers.EscapeForSingleQuotedShell(file));
            commandBuilder.Append("' || true; fi; ");
        }

        return commandBuilder.ToString();
    }

    public string BuildEntryPermissionsCommand(string normalizedTarget, bool isDirectory)
    {
        var chmodMode = isDirectory ? "700" : "600";
        return $"target='/target/{CaiRuntimePathHelpers.EscapeForSingleQuotedShell(normalizedTarget)}'; " +
               "if [ -e \"$target\" ]; then chmod " + chmodMode + " \"$target\"; fi; " +
               "if [ -e \"$target\" ]; then chown 1000:1000 \"$target\" || true; fi";
    }
}
