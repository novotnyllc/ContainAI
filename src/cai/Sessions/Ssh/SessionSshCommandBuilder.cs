namespace ContainAI.Cli.Host;

internal interface ISessionSshCommandBuilder
{
    List<string> BuildSshArguments(SessionCommandOptions options, string sshPort, string remoteCommand, bool forceTty);

    string BuildDetachedRemoteCommand(IReadOnlyList<string> commandArgs);

    string BuildForegroundRemoteCommand(IReadOnlyList<string> commandArgs, bool loginShell);
}

internal sealed class SessionSshCommandBuilder : ISessionSshCommandBuilder
{
    public List<string> BuildSshArguments(SessionCommandOptions options, string sshPort, string remoteCommand, bool forceTty)
    {
        var args = new List<string>
        {
            "-o", $"HostName={SessionRuntimeConstants.SshHost}",
            "-o", $"Port={sshPort}",
            "-o", "User=agent",
            "-o", $"IdentityFile={SessionRuntimePathHelpers.ResolveSshPrivateKeyPath()}",
            "-o", "IdentitiesOnly=yes",
            "-o", $"UserKnownHostsFile={SessionRuntimePathHelpers.ResolveKnownHostsFilePath()}",
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

    public string BuildDetachedRemoteCommand(IReadOnlyList<string> commandArgs)
    {
        var inner = JoinForShell(commandArgs);
        return $"cd /home/agent/workspace && nohup {inner} </dev/null >/dev/null 2>&1 & echo $!";
    }

    public string BuildForegroundRemoteCommand(IReadOnlyList<string> commandArgs, bool loginShell)
    {
        if (!loginShell)
        {
            return $"cd /home/agent/workspace && {JoinForShell(commandArgs)}";
        }

        var inner = JoinForShell(commandArgs);
        var escaped = SessionRuntimeTextHelpers.EscapeForSingleQuotedShell(inner);
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
            : $"'{SessionRuntimeTextHelpers.EscapeForSingleQuotedShell(value)}'";
}
