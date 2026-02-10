using System.CommandLine;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Commands.Runtime;

internal static class ExecCommandBuilder
{
    internal static Command Build(ICaiCommandRuntime runtime)
    {
        var command = new Command("exec", "Execute a command through SSH.");

        var workspaceOption = RuntimeCommandOptionFactory.CreateWorkspaceOption("Workspace path for command execution.");
        var containerOption = RuntimeCommandOptionFactory.CreateContainerOption();
        var templateOption = RuntimeCommandOptionFactory.CreateTemplateOption();
        var channelOption = RuntimeCommandOptionFactory.CreateChannelOption();
        var dataVolumeOption = RuntimeCommandOptionFactory.CreateDataVolumeOption();
        var configOption = RuntimeCommandOptionFactory.CreateConfigOption();
        var freshOption = RuntimeCommandOptionFactory.CreateFreshOption();
        var forceOption = RuntimeCommandOptionFactory.CreateForceOption();
        var quietOption = RuntimeCommandOptionFactory.CreateQuietOption();
        var verboseOption = RuntimeCommandOptionFactory.CreateVerboseOption();
        var debugOption = RuntimeCommandOptionFactory.CreateDebugOption();
        var commandArgs = new Argument<string[]>("command")
        {
            Arity = ArgumentArity.OneOrMore,
            Description = "Command and arguments passed to ssh.",
        };

        RuntimeCommandOptionFactory.AddOptions(
            command,
            workspaceOption,
            containerOption,
            templateOption,
            channelOption,
            dataVolumeOption,
            configOption,
            freshOption,
            forceOption,
            quietOption,
            verboseOption,
            debugOption);
        command.Arguments.Add(commandArgs);

        command.SetAction((parseResult, cancellationToken) => runtime.RunExecAsync(
            new ExecCommandOptions(
                Workspace: parseResult.GetValue(workspaceOption),
                Quiet: parseResult.GetValue(quietOption),
                Verbose: parseResult.GetValue(verboseOption),
                Container: parseResult.GetValue(containerOption),
                Template: parseResult.GetValue(templateOption),
                Channel: parseResult.GetValue(channelOption),
                DataVolume: parseResult.GetValue(dataVolumeOption),
                Config: parseResult.GetValue(configOption),
                Fresh: parseResult.GetValue(freshOption),
                Force: parseResult.GetValue(forceOption),
                Debug: parseResult.GetValue(debugOption),
                CommandArgs: parseResult.GetValue(commandArgs) ?? Array.Empty<string>()),
            cancellationToken));

        return command;
    }
}
