using System.Text;
using ContainAI.Cli.Host.RuntimeSupport.Paths;

namespace ContainAI.Cli.Host.Importing.Transfer;

internal interface IImportManifestTargetCommandBuilder
{
    string BuildEnsureDirectoryCommand(string targetPath, bool isSecret);

    string BuildEnsureFileCommand(ManifestEntry entry);
}
