using System.Net.NetworkInformation;
using ContainAI.Cli.Host.Sessions.Infrastructure;
using ContainAI.Cli.Host.Sessions.Models;

namespace ContainAI.Cli.Host.Sessions.Provisioning;

internal interface ISessionSshPortAllocator
{
    Task<ResolutionResult<string>> AllocateSshPortAsync(string context, CancellationToken cancellationToken);
}
