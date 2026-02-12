using ContainAI.Cli.Host.Sessions.Infrastructure;
using ContainAI.Cli.Host.Sessions.Models;

namespace ContainAI.Cli.Host.Sessions.Ssh;

internal interface ISessionSshCommandBuilder
{
    List<string> BuildSshArguments(SessionCommandOptions options, string sshPort, string remoteCommand, bool forceTty);

    string BuildDetachedRemoteCommand(IReadOnlyList<string> commandArgs);

    string BuildForegroundRemoteCommand(IReadOnlyList<string> commandArgs, bool loginShell);
}
