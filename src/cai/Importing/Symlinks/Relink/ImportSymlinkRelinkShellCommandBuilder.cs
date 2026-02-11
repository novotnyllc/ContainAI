using System.Text;
using ContainAI.Cli.Host.RuntimeSupport.Paths;

namespace ContainAI.Cli.Host.Importing.Symlinks;

internal interface IImportSymlinkRelinkShellCommandBuilder
{
    string Build(IReadOnlyList<ImportSymlinkRelinkOperation> operations);
}

internal sealed class ImportSymlinkRelinkShellCommandBuilder : IImportSymlinkRelinkShellCommandBuilder
{
    public string Build(IReadOnlyList<ImportSymlinkRelinkOperation> operations)
    {
        ArgumentNullException.ThrowIfNull(operations);

        var commandBuilder = new StringBuilder();
        foreach (var operation in operations)
        {
            commandBuilder.Append("link='");
            commandBuilder.Append(CaiRuntimePathHelpers.EscapeForSingleQuotedShell(operation.LinkPath));
            commandBuilder.Append("'; ");
            commandBuilder.Append("mkdir -p \"$(dirname \"$link\")\"; ");
            commandBuilder.Append("rm -rf -- \"$link\"; ");
            commandBuilder.Append("ln -sfn -- '");
            commandBuilder.Append(CaiRuntimePathHelpers.EscapeForSingleQuotedShell(operation.RelativeTarget));
            commandBuilder.Append("' \"$link\"; ");
        }

        return commandBuilder.ToString();
    }
}
