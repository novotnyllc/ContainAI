using ContainAI.Cli.Host.Sessions.Execution.Ssh;
using ContainAI.Cli.Host.Sessions.Models;

namespace ContainAI.Cli.Host.Sessions.Execution.Modes;

internal sealed class SessionShellModeExecutor : ISessionShellModeExecutor
{
    private readonly ISessionSshExecutionService sshExecutionService;

    public SessionShellModeExecutor(ISessionSshExecutionService sessionSshExecutionService)
        => sshExecutionService = sessionSshExecutionService ?? throw new ArgumentNullException(nameof(sessionSshExecutionService));

    public async Task<int> RunAsync(SessionCommandOptions options, EnsuredSession session, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        ArgumentNullException.ThrowIfNull(session);

        const string remoteCommand = "cd /home/agent/workspace && exec $SHELL -l";
        return await sshExecutionService
            .RunInteractiveAsync(options, session.SshPort, remoteCommand, forceTty: true, cancellationToken)
            .ConfigureAwait(false);
    }
}
