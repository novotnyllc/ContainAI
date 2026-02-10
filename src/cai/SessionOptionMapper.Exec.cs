using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed partial class SessionOptionMapper
{
    public SessionCommandOptions FromExec(ExecCommandOptions options)
        => SessionCommandOptions.Create(SessionMode.Exec) with
        {
            Workspace = options.Workspace,
            DataVolume = options.DataVolume,
            ExplicitConfig = options.Config,
            Container = options.Container,
            Template = options.Template,
            Channel = options.Channel,
            Fresh = options.Fresh,
            Force = options.Force,
            Quiet = options.Quiet,
            Verbose = options.Verbose,
            Debug = options.Debug,
            CommandArgs = options.CommandArgs,
            EnvVars = [],
        };
}
