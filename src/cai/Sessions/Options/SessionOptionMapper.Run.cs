using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed partial class SessionOptionMapper
{
    public SessionCommandOptions FromRun(RunCommandOptions options)
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
}
