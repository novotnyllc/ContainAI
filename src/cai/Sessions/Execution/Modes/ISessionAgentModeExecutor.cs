using ContainAI.Cli.Host.Sessions.Execution.Ssh;
using ContainAI.Cli.Host.Sessions.Models;
using ContainAI.Cli.Host.Sessions.Ssh;

namespace ContainAI.Cli.Host.Sessions.Execution.Modes;

internal interface ISessionAgentModeExecutor
{
    Task<int> RunAsync(SessionCommandOptions options, EnsuredSession session, CancellationToken cancellationToken);
}
