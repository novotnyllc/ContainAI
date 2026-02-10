namespace ContainAI.Cli.Host;

internal sealed partial class SessionRemoteExecutor
{
    private readonly TextWriter stdout;
    private readonly TextWriter stderr;
    private readonly IConsoleInputState consoleInputState;
    private readonly ISessionSshCommandBuilder sshCommandBuilder;

    public SessionRemoteExecutor(
        TextWriter standardOutput,
        TextWriter standardError,
        IConsoleInputState sessionConsoleInputState)
        : this(standardOutput, standardError, sessionConsoleInputState, new SessionSshCommandBuilder())
    {
    }

    internal SessionRemoteExecutor(
        TextWriter standardOutput,
        TextWriter standardError,
        IConsoleInputState sessionConsoleInputState,
        ISessionSshCommandBuilder sessionSshCommandBuilder)
    {
        stdout = standardOutput;
        stderr = standardError;
        consoleInputState = sessionConsoleInputState;
        sshCommandBuilder = sessionSshCommandBuilder ?? throw new ArgumentNullException(nameof(sessionSshCommandBuilder));
    }

    public Task<int> ExecuteAsync(SessionCommandOptions options, EnsuredSession session, CancellationToken cancellationToken)
        => options.Mode switch
        {
            SessionMode.Run => RunAgentAsync(options, session, cancellationToken),
            SessionMode.Shell => RunShellAsync(options, session, cancellationToken),
            SessionMode.Exec => RunExecAsync(options, session, cancellationToken),
            _ => Task.FromResult(1),
        };
}
