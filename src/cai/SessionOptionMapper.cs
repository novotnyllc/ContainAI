using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal static class SessionOptionMapper
{
    public static SessionCommandOptions FromRun(RunCommandOptions options)
        => SessionCommandOptions.Create(SessionMode.Run) with
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
            Credentials = options.Credentials,
            AcknowledgeCredentialRisk = options.AcknowledgeCredentialRisk,
            Fresh = options.Fresh,
            Force = options.Force,
            Detached = options.Detached,
            Quiet = options.Quiet,
            Verbose = options.Verbose,
            Debug = options.Debug,
            DryRun = options.DryRun,
            CommandArgs = options.CommandArgs,
            EnvVars = [.. options.Env],
        };

    public static SessionCommandOptions FromShell(ShellCommandOptions options)
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

    public static SessionCommandOptions FromExec(ExecCommandOptions options)
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
