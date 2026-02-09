using System.CommandLine;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli;

internal static partial class RuntimeCommandsBuilder
{
    internal static Command CreateShellCommand(ICaiCommandRuntime runtime)
    {
        var command = new Command("shell", "Open an interactive login shell.");

        var workspaceOption = CreateWorkspaceOption("Workspace path for shell execution.");
        var dataVolumeOption = CreateDataVolumeOption();
        var configOption = CreateConfigOption();
        var containerOption = CreateContainerOption();
        var freshOption = CreateFreshOption();
        var restartOption = CreateRestartOption();
        var resetOption = new Option<bool>("--reset")
        {
            Description = "Create a reset volume shell session.",
        };
        var forceOption = CreateForceOption();
        var quietOption = CreateQuietOption();
        var verboseOption = CreateVerboseOption();
        var debugOption = CreateDebugOption();
        var dryRunOption = CreateDryRunOption();
        var imageTagOption = new Option<string?>("--image-tag")
        {
            Description = "Override image tag.",
        };
        var templateOption = CreateTemplateOption();
        var channelOption = CreateChannelOption();
        var memoryOption = CreateMemoryOption();
        var cpusOption = CreateCpusOption();
        var pathArgument = new Argument<string?>("path")
        {
            Arity = ArgumentArity.ZeroOrOne,
            Description = "Workspace path (optional positional form).",
        };

        AddOptions(
            command,
            workspaceOption,
            dataVolumeOption,
            configOption,
            containerOption,
            freshOption,
            restartOption,
            resetOption,
            forceOption,
            quietOption,
            verboseOption,
            debugOption,
            dryRunOption,
            imageTagOption,
            templateOption,
            channelOption,
            memoryOption,
            cpusOption);
        command.Arguments.Add(pathArgument);

        command.SetAction((parseResult, cancellationToken) =>
        {
            var workspace = parseResult.GetValue(workspaceOption);
            var positionalPath = parseResult.GetValue(pathArgument);
            if (string.IsNullOrWhiteSpace(workspace) && !string.IsNullOrWhiteSpace(positionalPath))
            {
                workspace = positionalPath;
            }

            return runtime.RunShellAsync(
                new ShellCommandOptions(
                    Workspace: workspace,
                    Fresh: parseResult.GetValue(freshOption) || parseResult.GetValue(restartOption),
                    Reset: parseResult.GetValue(resetOption),
                    Quiet: parseResult.GetValue(quietOption),
                    Verbose: parseResult.GetValue(verboseOption),
                    DataVolume: parseResult.GetValue(dataVolumeOption),
                    Config: parseResult.GetValue(configOption),
                    Container: parseResult.GetValue(containerOption),
                    Force: parseResult.GetValue(forceOption),
                    Debug: parseResult.GetValue(debugOption),
                    DryRun: parseResult.GetValue(dryRunOption),
                    ImageTag: parseResult.GetValue(imageTagOption),
                    Template: parseResult.GetValue(templateOption),
                    Channel: parseResult.GetValue(channelOption),
                    Memory: parseResult.GetValue(memoryOption),
                    Cpus: parseResult.GetValue(cpusOption),
                    CommandArgs: Array.Empty<string>()),
                cancellationToken);
        });

        return command;
    }
}
