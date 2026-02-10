namespace ContainAI.Cli.Host;

internal sealed partial class SessionSshCommandBuilder
{
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
        var escaped = SessionRuntimeInfrastructure.EscapeForSingleQuotedShell(inner);
        return $"cd /home/agent/workspace && bash -lc '{escaped}'";
    }
}
