using ContainAI.Cli.Host.Sessions.Execution.Modes;
using ContainAI.Cli.Host.Sessions.Execution.Ssh;
using ContainAI.Cli.Host.Sessions.Models;
using ContainAI.Cli.Host.Sessions.Ssh;

namespace ContainAI.Cli.Host.Sessions.Execution;

internal sealed class SessionRemoteExecutor
{
    private readonly ISessionAgentModeExecutor agentModeExecutor;
    private readonly ISessionShellModeExecutor shellModeExecutor;
    private readonly ISessionExecModeExecutor execModeExecutor;

    public SessionRemoteExecutor(
        TextWriter standardOutput,
        TextWriter standardError,
        IConsoleInputState sessionConsoleInputState)
        : this(
            CreateAgentModeExecutor(standardOutput, standardError, sessionConsoleInputState),
            CreateShellModeExecutor(standardError),
            CreateExecModeExecutor(standardError, sessionConsoleInputState))
    {
    }

    internal SessionRemoteExecutor(
        ISessionAgentModeExecutor sessionAgentModeExecutor,
        ISessionShellModeExecutor sessionShellModeExecutor,
        ISessionExecModeExecutor sessionExecModeExecutor)
    {
        agentModeExecutor = sessionAgentModeExecutor ?? throw new ArgumentNullException(nameof(sessionAgentModeExecutor));
        shellModeExecutor = sessionShellModeExecutor ?? throw new ArgumentNullException(nameof(sessionShellModeExecutor));
        execModeExecutor = sessionExecModeExecutor ?? throw new ArgumentNullException(nameof(sessionExecModeExecutor));
    }

    public Task<int> ExecuteAsync(SessionCommandOptions options, EnsuredSession session, CancellationToken cancellationToken)
        => options.Mode switch
        {
            SessionMode.Run => agentModeExecutor.RunAsync(options, session, cancellationToken),
            SessionMode.Shell => shellModeExecutor.RunAsync(options, session, cancellationToken),
            SessionMode.Exec => execModeExecutor.RunAsync(options, session, cancellationToken),
            _ => Task.FromResult(1),
        };

    private static SessionAgentModeExecutor CreateAgentModeExecutor(
        TextWriter standardOutput,
        TextWriter standardError,
        IConsoleInputState sessionConsoleInputState)
    {
        var sshCommandBuilder = new SessionSshCommandBuilder();
        var sshExecutionService = new SessionSshExecutionService(sshCommandBuilder, standardError);
        return new SessionAgentModeExecutor(
            standardOutput,
            standardError,
            sessionConsoleInputState,
            sshCommandBuilder,
            sshExecutionService);
    }

    private static SessionShellModeExecutor CreateShellModeExecutor(TextWriter standardError)
    {
        var sshCommandBuilder = new SessionSshCommandBuilder();
        var sshExecutionService = new SessionSshExecutionService(sshCommandBuilder, standardError);
        return new SessionShellModeExecutor(sshExecutionService);
    }

    private static SessionExecModeExecutor CreateExecModeExecutor(
        TextWriter standardError,
        IConsoleInputState sessionConsoleInputState)
    {
        var sshCommandBuilder = new SessionSshCommandBuilder();
        var sshExecutionService = new SessionSshExecutionService(sshCommandBuilder, standardError);
        return new SessionExecModeExecutor(
            standardError,
            sessionConsoleInputState,
            sshCommandBuilder,
            sshExecutionService);
    }
}
