using System.Text;
using ContainAI.Cli.Host.RuntimeSupport.Paths;

namespace ContainAI.Cli.Host.Importing.Transfer.SecretPermissions;

internal interface ISecretPermissionCommandBuilder
{
    string BuildBulkPermissionsCommand(IReadOnlyCollection<string> secretDirectories, IReadOnlyCollection<string> secretFiles);

    string BuildEntryPermissionsCommand(string normalizedTarget, bool isDirectory);
}
