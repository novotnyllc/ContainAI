using ContainAI.Cli.Abstractions;
using ContainAI.Cli.Host.Sessions.Models;

namespace ContainAI.Cli.Host.Sessions.Options;

internal interface ISessionOptionMapper
{
    SessionCommandOptions FromRun(RunCommandOptions options);

    SessionCommandOptions FromShell(ShellCommandOptions options);

    SessionCommandOptions FromExec(ExecCommandOptions options);
}
