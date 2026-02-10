using System.CommandLine;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Commands.Maintenance;

internal static class StopCommandBuilder
{
    internal static Command Build(ICaiCommandRuntime runtime)
    {
        var command = new Command("stop", "Stop managed containers.");
        var allOption = new Option<bool>("--all");
        var containerOption = new Option<string?>("--container");
        var removeOption = new Option<bool>("--remove");
        var forceOption = new Option<bool>("--force");
        var exportOption = new Option<bool>("--export");
        var verboseOption = new Option<bool>("--verbose");

        command.Options.Add(allOption);
        command.Options.Add(containerOption);
        command.Options.Add(removeOption);
        command.Options.Add(forceOption);
        command.Options.Add(exportOption);
        command.Options.Add(verboseOption);
        command.SetAction((parseResult, cancellationToken) =>
            runtime.RunStopAsync(
                new StopCommandOptions(
                    All: parseResult.GetValue(allOption),
                    Container: parseResult.GetValue(containerOption),
                    Remove: parseResult.GetValue(removeOption),
                    Force: parseResult.GetValue(forceOption),
                    Export: parseResult.GetValue(exportOption),
                    Verbose: parseResult.GetValue(verboseOption)),
                cancellationToken));

        return command;
    }
}
