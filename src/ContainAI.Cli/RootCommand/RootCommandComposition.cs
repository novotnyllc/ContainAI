using System.CommandLine;
using ContainAI.Cli.Abstractions;
using ContainAI.Cli.Commands.Maintenance;
using ContainAI.Cli.Commands.Meta;
using ContainAI.Cli.Commands.Runtime;
using ContainAI.Cli.Host;

namespace ContainAI.Cli;

internal static class RootCommandComposition
{
    internal static RootCommand Create(ICaiCommandRuntime runtime, ICaiConsole console)
    {
        var root = new RootCommand("ContainAI native CLI")
        {
            TreatUnmatchedTokensAsErrors = true,
        };

        root.SetAction((_, cancellationToken) => runtime.RunRunAsync(
            new RunCommandOptions(
                Workspace: null,
                Fresh: false,
                Detached: false,
                Quiet: false,
                Verbose: false,
                Credentials: null,
                AcknowledgeCredentialRisk: false,
                DataVolume: null,
                Config: null,
                Container: null,
                Force: false,
                Debug: false,
                DryRun: false,
                ImageTag: null,
                Template: null,
                Channel: null,
                Memory: null,
                Cpus: null,
                Env: Array.Empty<string>(),
                CommandArgs: Array.Empty<string>()),
            cancellationToken));

        foreach (var command in BuildSubcommands(runtime, console, root))
        {
            root.Subcommands.Add(command);
        }

        return root;
    }

    private static Command[] BuildSubcommands(ICaiCommandRuntime runtime, ICaiConsole console, RootCommand root)
        =>
        [
            RunCommandBuilder.Build(runtime),
            ShellCommandBuilder.Build(runtime),
            ExecCommandBuilder.Build(runtime),
            DoctorCommandBuilder.Build(runtime),
            InstallCommandBuilder.Build(runtime),
            ExamplesCommandBuilder.Build(runtime),
            SetupCommandBuilder.Build(runtime),
            ValidateCommandBuilder.Build(runtime),
            DockerCommandBuilder.Build(runtime),
            ImportCommandBuilder.Build(runtime),
            ExportCommandBuilder.Build(runtime),
            SyncCommandBuilder.Build(runtime),
            StopCommandBuilder.Build(runtime),
            StatusCommandBuilder.Build(runtime),
            GcCommandBuilder.Build(runtime),
            SshCommandBuilder.Build(runtime),
            LinksCommandBuilder.Build(runtime),
            ConfigCommandBuilder.Build(runtime),
            ManifestCommandBuilder.Build(runtime),
            TemplateCommandBuilder.Build(runtime),
            UpdateCommandBuilder.Build(runtime),
            RefreshCommandBuilder.Build(runtime),
            UninstallCommandBuilder.Build(runtime),
            CompletionCommandBuilder.Build(root, console),
            VersionCommandBuilder.Build(runtime, console),
            SystemCommandBuilder.Build(runtime),
            AcpCommandBuilder.Build(runtime),
        ];
}
