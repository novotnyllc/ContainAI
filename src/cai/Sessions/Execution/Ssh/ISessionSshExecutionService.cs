using ContainAI.Cli.Host.Sessions.Infrastructure;
using ContainAI.Cli.Host.Sessions.Models;
using ContainAI.Cli.Host.Sessions.Ssh;

namespace ContainAI.Cli.Host.Sessions.Execution.Ssh;

internal interface ISessionSshExecutionService
{
    Task<int> RunInteractiveAsync(
        SessionCommandOptions options,
        string sshPort,
        string remoteCommand,
        bool forceTty,
        CancellationToken cancellationToken);

    Task<ProcessResult> RunCaptureAsync(
        SessionCommandOptions options,
        string sshPort,
        string remoteCommand,
        bool forceTty,
        CancellationToken cancellationToken);
}
