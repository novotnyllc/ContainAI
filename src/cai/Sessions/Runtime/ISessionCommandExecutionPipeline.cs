using ContainAI.Cli.Host.Sessions.Execution;
using ContainAI.Cli.Host.Sessions.Models;
using ContainAI.Cli.Host.Sessions.Provisioning;
using ContainAI.Cli.Host.Sessions.Resolution.Orchestration;
using ContainAI.Cli.Host.Sessions.State;

namespace ContainAI.Cli.Host.Sessions.Runtime;

internal interface ISessionCommandExecutionPipeline
{
    Task<int> RunAsync(SessionCommandOptions options, CancellationToken cancellationToken);
}
