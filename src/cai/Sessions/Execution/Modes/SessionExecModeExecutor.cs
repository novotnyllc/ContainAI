using ContainAI.Cli.Host.Sessions.Execution.Ssh;
using ContainAI.Cli.Host.Sessions.Models;
using ContainAI.Cli.Host.Sessions.Ssh;

namespace ContainAI.Cli.Host.Sessions.Execution.Modes;

internal sealed class SessionExecModeExecutor : ISessionExecModeExecutor
{
    private readonly TextWriter standardError;
    private readonly IConsoleInputState consoleInputState;
    private readonly ISessionSshCommandBuilder sshCommandBuilder;
    private readonly ISessionSshExecutionService sshExecutionService;

    public SessionExecModeExecutor(
        TextWriter standardError,
        IConsoleInputState sessionConsoleInputState,
        ISessionSshCommandBuilder sessionSshCommandBuilder,
        ISessionSshExecutionService sessionSshExecutionService)
    {
        this.standardError = standardError ?? throw new ArgumentNullException(nameof(standardError));
        consoleInputState = sessionConsoleInputState ?? throw new ArgumentNullException(nameof(sessionConsoleInputState));
        sshCommandBuilder = sessionSshCommandBuilder ?? throw new ArgumentNullException(nameof(sessionSshCommandBuilder));
        sshExecutionService = sessionSshExecutionService ?? throw new ArgumentNullException(nameof(sessionSshExecutionService));
    }

    public async Task<int> RunAsync(SessionCommandOptions options, EnsuredSession session, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        ArgumentNullException.ThrowIfNull(session);

        if (options.CommandArgs.Count == 0)
        {
            await standardError.WriteLineAsync("No command specified. Usage: cai exec [options] [--] <command> [args...]").ConfigureAwait(false);
            return 1;
        }

        var remoteCommand = sshCommandBuilder.BuildForegroundRemoteCommand(options.CommandArgs, loginShell: true);
        return await sshExecutionService
            .RunInteractiveAsync(
                options,
                session.SshPort,
                remoteCommand,
                forceTty: !consoleInputState.IsInputRedirected,
                cancellationToken)
            .ConfigureAwait(false);
    }
}
