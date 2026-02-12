using ContainAI.Cli.Host.Sessions.Infrastructure;
using ContainAI.Cli.Host.Sessions.Models;

namespace ContainAI.Cli.Host.Sessions.Provisioning;

internal interface ISessionContainerRunCommandBuilder
{
    IReadOnlyList<string> BuildCommand(SessionCommandOptions options, ResolvedTarget resolved, string sshPort, string image);
}
