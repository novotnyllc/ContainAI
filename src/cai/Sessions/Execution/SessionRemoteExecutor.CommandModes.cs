namespace ContainAI.Cli.Host;

internal sealed partial class SessionRemoteExecutor
{
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
}
