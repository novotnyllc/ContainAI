using System.Text;
using ContainAI.Cli.Host.RuntimeSupport.Paths;

namespace ContainAI.Cli.Host.Importing.Symlinks;

internal interface IImportSymlinkRelinkShellCommandBuilder
{
    string Build(IReadOnlyList<ImportSymlinkRelinkOperation> operations);
}
