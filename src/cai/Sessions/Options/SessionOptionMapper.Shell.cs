using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed partial class SessionOptionMapper
{
    public SessionCommandOptions FromShell(ShellCommandOptions options)
        => SessionCommandOptions.Create(SessionMode.Shell) with
        {
            Workspace = options.Workspace,
            DataVolume = options.DataVolume,
            ExplicitConfig = options.Config,
            Container = options.Container,
            Template = options.Template,
            ImageTag = options.ImageTag,
            Channel = options.Channel,
            Memory = options.Memory,
            Cpus = options.Cpus,
            Fresh = options.Fresh,
            Reset = options.Reset,
            Force = options.Force,
            Quiet = options.Quiet,
            Verbose = options.Verbose,
            Debug = options.Debug,
            DryRun = options.DryRun,
            CommandArgs = options.CommandArgs,
            EnvVars = [],
        };
}
