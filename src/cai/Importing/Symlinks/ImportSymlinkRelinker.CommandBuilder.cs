using System.Text;

namespace ContainAI.Cli.Host.Importing.Symlinks;

internal sealed partial class ImportSymlinkRelinker
{
    private static StringBuilder BuildRelinkShellCommand(IReadOnlyList<(string LinkPath, string RelativeTarget)> operations)
    {
        var commandBuilder = new StringBuilder();
        foreach (var operation in operations)
        {
            commandBuilder.Append("link='");
            commandBuilder.Append(EscapeForSingleQuotedShell(operation.LinkPath));
            commandBuilder.Append("'; ");
            commandBuilder.Append("mkdir -p \"$(dirname \"$link\")\"; ");
            commandBuilder.Append("rm -rf -- \"$link\"; ");
            commandBuilder.Append("ln -sfn -- '");
            commandBuilder.Append(EscapeForSingleQuotedShell(operation.RelativeTarget));
            commandBuilder.Append("' \"$link\"; ");
        }

        return commandBuilder;
    }
}
