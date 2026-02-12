using ContainAI.Cli.Host.Sessions.Execution.Ssh;
using ContainAI.Cli.Host.Sessions.Models;
using ContainAI.Cli.Host.Sessions.Ssh;

namespace ContainAI.Cli.Host.Sessions.Execution.Modes;

internal interface ISessionAgentModeExecutor
{
    Task<int> RunAsync(SessionCommandOptions options, EnsuredSession session, CancellationToken cancellationToken);
}

internal sealed class SessionAgentModeExecutor : ISessionAgentModeExecutor
{
    private readonly TextWriter standardOutput;
    private readonly TextWriter standardError;
    private readonly IConsoleInputState consoleInputState;
    private readonly ISessionSshCommandBuilder sshCommandBuilder;
    private readonly ISessionSshExecutionService sshExecutionService;

    public SessionAgentModeExecutor(
        TextWriter standardOutput,
        TextWriter standardError,
        IConsoleInputState sessionConsoleInputState,
        ISessionSshCommandBuilder sessionSshCommandBuilder,
        ISessionSshExecutionService sessionSshExecutionService)
    {
        this.standardOutput = standardOutput ?? throw new ArgumentNullException(nameof(standardOutput));
        this.standardError = standardError ?? throw new ArgumentNullException(nameof(standardError));
        consoleInputState = sessionConsoleInputState ?? throw new ArgumentNullException(nameof(sessionConsoleInputState));
        sshCommandBuilder = sessionSshCommandBuilder ?? throw new ArgumentNullException(nameof(sessionSshCommandBuilder));
        sshExecutionService = sessionSshExecutionService ?? throw new ArgumentNullException(nameof(sessionSshExecutionService));
    }

    public async Task<int> RunAsync(SessionCommandOptions options, EnsuredSession session, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        ArgumentNullException.ThrowIfNull(session);

        var runCommand = new List<string>();
        runCommand.AddRange(options.EnvVars);
        if (options.CommandArgs.Count > 0)
        {
            runCommand.AddRange(options.CommandArgs);
        }
        else
        {
            runCommand.Add("claude");
        }

        if (options.Detached)
        {
            var remoteDetached = sshCommandBuilder.BuildDetachedRemoteCommand(runCommand);
            var sshResult = await sshExecutionService
                .RunCaptureAsync(options, session.SshPort, remoteDetached, forceTty: false, cancellationToken)
                .ConfigureAwait(false);
            if (sshResult.ExitCode != 0)
            {
                if (!string.IsNullOrWhiteSpace(sshResult.StandardError))
                {
                    await standardError.WriteLineAsync(sshResult.StandardError.Trim()).ConfigureAwait(false);
                }

                return sshResult.ExitCode;
            }

            var pid = sshResult.StandardOutput.Trim();
            if (!int.TryParse(pid, out _))
            {
                await standardError.WriteLineAsync("Background command failed: could not determine remote PID.").ConfigureAwait(false);
                return 1;
            }

            await standardOutput.WriteLineAsync($"Command running in background (PID: {pid})").ConfigureAwait(false);
            return 0;
        }

        var remoteForeground = sshCommandBuilder.BuildForegroundRemoteCommand(runCommand, loginShell: false);
        return await sshExecutionService
            .RunInteractiveAsync(
                options,
                session.SshPort,
                remoteForeground,
                forceTty: !consoleInputState.IsInputRedirected,
                cancellationToken)
            .ConfigureAwait(false);
    }
}
