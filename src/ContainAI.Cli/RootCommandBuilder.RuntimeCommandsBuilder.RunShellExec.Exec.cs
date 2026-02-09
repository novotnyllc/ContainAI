using System.CommandLine;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli;

internal static partial class RuntimeCommandsBuilder
{
    internal static Command CreateExecCommand(ICaiCommandRuntime runtime)
    {
        var command = new Command("exec", "Execute a command through SSH.");

        var workspaceOption = CreateWorkspaceOption("Workspace path for command execution.");
        var containerOption = CreateContainerOption();
        var templateOption = CreateTemplateOption();
        var channelOption = CreateChannelOption();
        var dataVolumeOption = CreateDataVolumeOption();
        var configOption = CreateConfigOption();
        var freshOption = CreateFreshOption();
        var forceOption = CreateForceOption();
        var quietOption = CreateQuietOption();
        var verboseOption = CreateVerboseOption();
        var debugOption = CreateDebugOption();
        var commandArgs = new Argument<string[]>("command")
        {
            Arity = ArgumentArity.OneOrMore,
            Description = "Command and arguments passed to ssh.",
        };

        AddOptions(
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

        command.SetAction((parseResult, cancellationToken) =>
        {
            return runtime.RunExecAsync(
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
                cancellationToken);
        });

        return command;
    }
}
