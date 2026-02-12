using ContainAI.Cli.Host.RuntimeSupport.Docker;

namespace ContainAI.Cli.Host.Importing.Transfer.SecretPermissions;

internal interface ISecretPermissionDockerExecutor
{
    Task<int> ExecuteAsync(string volume, string shellCommand, CancellationToken cancellationToken);
}
