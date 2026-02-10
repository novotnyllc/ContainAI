using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal interface ISessionOptionMapper
{
    SessionCommandOptions FromRun(RunCommandOptions options);

    SessionCommandOptions FromShell(ShellCommandOptions options);

    SessionCommandOptions FromExec(ExecCommandOptions options);
}

internal sealed partial class SessionOptionMapper : ISessionOptionMapper;
