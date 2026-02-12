using ContainAI.Cli.Host.Sessions.Infrastructure;
using ContainAI.Cli.Host.Sessions.Models;

namespace ContainAI.Cli.Host.Sessions.Provisioning;

internal interface ISessionSshPortReadinessService
{
    Task<bool> WaitForSshPortAsync(string sshPort, CancellationToken cancellationToken);
}
