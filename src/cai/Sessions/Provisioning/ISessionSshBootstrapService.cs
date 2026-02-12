using ContainAI.Cli.Host.Sessions.Models;

namespace ContainAI.Cli.Host.Sessions.Provisioning;

internal interface ISessionSshBootstrapService
{
    Task<ResolutionResult<bool>> EnsureSshBootstrapAsync(
        ResolvedTarget resolved,
        string sshPort,
        CancellationToken cancellationToken);
}
