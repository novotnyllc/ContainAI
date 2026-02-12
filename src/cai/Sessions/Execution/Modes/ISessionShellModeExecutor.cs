using ContainAI.Cli.Host.Sessions.Execution.Ssh;
using ContainAI.Cli.Host.Sessions.Models;

namespace ContainAI.Cli.Host.Sessions.Execution.Modes;

internal interface ISessionShellModeExecutor
{
    Task<int> RunAsync(SessionCommandOptions options, EnsuredSession session, CancellationToken cancellationToken);
}
