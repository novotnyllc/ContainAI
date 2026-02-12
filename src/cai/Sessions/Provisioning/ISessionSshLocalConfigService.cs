using ContainAI.Cli.Host.Sessions.Models;

namespace ContainAI.Cli.Host.Sessions.Provisioning;

internal interface ISessionSshLocalConfigService
{
    Task<ResolutionResult<bool>> EnsureSshKeyPairAsync(CancellationToken cancellationToken);

    Task<ResolutionResult<bool>> UpdateKnownHostsAsync(string containerName, string sshPort, CancellationToken cancellationToken);

    Task<ResolutionResult<bool>> EnsureSshHostConfigAsync(string containerName, string sshPort, CancellationToken cancellationToken);
}
