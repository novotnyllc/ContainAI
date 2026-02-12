using ContainAI.Cli.Host.Sessions.Infrastructure;
using ContainAI.Cli.Host.Sessions.Models;

namespace ContainAI.Cli.Host.Sessions.Provisioning;

internal interface ISessionSshKeyPairService
{
    Task<ResolutionResult<bool>> EnsureSshKeyPairAsync(CancellationToken cancellationToken);
}
