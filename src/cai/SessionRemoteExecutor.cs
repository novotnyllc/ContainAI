namespace ContainAI.Cli.Host;

internal sealed class SessionRemoteExecutor
{
    private readonly TextWriter stdout;
    private readonly TextWriter stderr;
    private readonly IConsoleInputState consoleInputState;

    public SessionRemoteExecutor(TextWriter standardOutput, TextWriter standardError, IConsoleInputState sessionConsoleInputState)
    {
        stdout = standardOutput;
        stderr = standardError;
        consoleInputState = sessionConsoleInputState;
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
            var remoteDetached = BuildDetachedRemoteCommand(runCommand);
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

        var remoteForeground = BuildForegroundRemoteCommand(runCommand, loginShell: false);
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

        var remoteCommand = BuildForegroundRemoteCommand(options.CommandArgs, loginShell: true);
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
        var args = BuildSshArguments(options, sshPort, remoteCommand, forceTty);
        return await SessionRuntimeInfrastructure.RunProcessInteractiveAsync("ssh", args, stderr, cancellationToken).ConfigureAwait(false);
    }

    private static async Task<ProcessResult> RunSshCaptureAsync(
        SessionCommandOptions options,
        string sshPort,
        string remoteCommand,
        bool forceTty,
        CancellationToken cancellationToken)
    {
        var args = BuildSshArguments(options, sshPort, remoteCommand, forceTty);
        return await SessionRuntimeInfrastructure.RunProcessCaptureAsync("ssh", args, cancellationToken).ConfigureAwait(false);
    }

    private static List<string> BuildSshArguments(SessionCommandOptions options, string sshPort, string remoteCommand, bool forceTty)
    {
        var args = new List<string>
        {
            "-o", $"HostName={SessionRuntimeConstants.SshHost}",
            "-o", $"Port={sshPort}",
            "-o", "User=agent",
            "-o", $"IdentityFile={SessionRuntimeInfrastructure.ResolveSshPrivateKeyPath()}",
            "-o", "IdentitiesOnly=yes",
            "-o", $"UserKnownHostsFile={SessionRuntimeInfrastructure.ResolveKnownHostsFilePath()}",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "PreferredAuthentications=publickey",
            "-o", "GSSAPIAuthentication=no",
            "-o", "PasswordAuthentication=no",
            "-o", "AddressFamily=inet",
            "-o", "ConnectTimeout=10",
        };

        if (options.Quiet)
        {
            args.Add("-q");
        }

        if (options.Verbose)
        {
            args.Add("-v");
        }

        if (forceTty)
        {
            args.Add("-tt");
        }

        args.Add(SessionRuntimeConstants.SshHost);
        args.Add(remoteCommand);
        return args;
    }

    private static string BuildDetachedRemoteCommand(IReadOnlyList<string> commandArgs)
    {
        var inner = JoinForShell(commandArgs);
        return $"cd /home/agent/workspace && nohup {inner} </dev/null >/dev/null 2>&1 & echo $!";
    }

    private static string BuildForegroundRemoteCommand(IReadOnlyList<string> commandArgs, bool loginShell)
    {
        if (!loginShell)
        {
            return $"cd /home/agent/workspace && {JoinForShell(commandArgs)}";
        }

        var inner = JoinForShell(commandArgs);
        var escaped = SessionRuntimeInfrastructure.EscapeForSingleQuotedShell(inner);
        return $"cd /home/agent/workspace && bash -lc '{escaped}'";
    }

    private static string JoinForShell(IReadOnlyList<string> args)
    {
        if (args.Count == 0)
        {
            return "true";
        }

        var escaped = new string[args.Count];
        for (var index = 0; index < args.Count; index++)
        {
            escaped[index] = QuoteBash(args[index]);
        }

        return string.Join(" ", escaped);
    }

    private static string QuoteBash(string value)
        => string.IsNullOrEmpty(value)
            ? "''"
            : $"'{SessionRuntimeInfrastructure.EscapeForSingleQuotedShell(value)}'";
}
