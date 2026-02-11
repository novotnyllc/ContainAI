namespace ContainAI.Cli.Host;

internal sealed class SessionRemoteExecutor
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

    private async Task<int> RunAgentAsync(SessionCommandOptions options, EnsuredSession session, CancellationToken cancellationToken)
    {
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
            var sshResult = await RunSshCaptureAsync(options, session.SshPort, remoteDetached, forceTty: false, cancellationToken).ConfigureAwait(false);
            if (sshResult.ExitCode != 0)
            {
                if (!string.IsNullOrWhiteSpace(sshResult.StandardError))
                {
                    await stderr.WriteLineAsync(sshResult.StandardError.Trim()).ConfigureAwait(false);
                }

                return sshResult.ExitCode;
            }

            var pid = sshResult.StandardOutput.Trim();
            if (!int.TryParse(pid, out _))
            {
                await stderr.WriteLineAsync("Background command failed: could not determine remote PID.").ConfigureAwait(false);
                return 1;
            }

            await stdout.WriteLineAsync($"Command running in background (PID: {pid})").ConfigureAwait(false);
            return 0;
        }

        var remoteForeground = sshCommandBuilder.BuildForegroundRemoteCommand(runCommand, loginShell: false);
        return await RunSshInteractiveAsync(
            options,
            session.SshPort,
            remoteForeground,
            forceTty: !consoleInputState.IsInputRedirected,
            cancellationToken).ConfigureAwait(false);
    }

    private async Task<int> RunShellAsync(SessionCommandOptions options, EnsuredSession session, CancellationToken cancellationToken)
    {
        const string remoteCommand = "cd /home/agent/workspace && exec $SHELL -l";
        return await RunSshInteractiveAsync(options, session.SshPort, remoteCommand, forceTty: true, cancellationToken).ConfigureAwait(false);
    }

    private async Task<int> RunExecAsync(SessionCommandOptions options, EnsuredSession session, CancellationToken cancellationToken)
    {
        if (options.CommandArgs.Count == 0)
        {
            await stderr.WriteLineAsync("No command specified. Usage: cai exec [options] [--] <command> [args...]").ConfigureAwait(false);
            return 1;
        }

        var remoteCommand = sshCommandBuilder.BuildForegroundRemoteCommand(options.CommandArgs, loginShell: true);
        return await RunSshInteractiveAsync(
            options,
            session.SshPort,
            remoteCommand,
            forceTty: !consoleInputState.IsInputRedirected,
            cancellationToken).ConfigureAwait(false);
    }

    private async Task<int> RunSshInteractiveAsync(
        SessionCommandOptions options,
        string sshPort,
        string remoteCommand,
        bool forceTty,
        CancellationToken cancellationToken)
    {
        var args = sshCommandBuilder.BuildSshArguments(options, sshPort, remoteCommand, forceTty);
        return await SessionRuntimeInfrastructure.RunProcessInteractiveAsync("ssh", args, stderr, cancellationToken).ConfigureAwait(false);
    }

    private async Task<ProcessResult> RunSshCaptureAsync(
        SessionCommandOptions options,
        string sshPort,
        string remoteCommand,
        bool forceTty,
        CancellationToken cancellationToken)
    {
        var args = sshCommandBuilder.BuildSshArguments(options, sshPort, remoteCommand, forceTty);
        return await SessionRuntimeInfrastructure.RunProcessCaptureAsync("ssh", args, cancellationToken).ConfigureAwait(false);
    }
}
