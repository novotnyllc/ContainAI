using System.CommandLine;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Commands.Maintenance;

internal static class RefreshCommandBuilder
{
    internal static Command Build(ICaiCommandRuntime runtime)
    {
        var command = new Command("refresh", "Refresh images and rebuild templates when requested.");
        var rebuildOption = new Option<bool>("--rebuild");
        var verboseOption = new Option<bool>("--verbose");

        command.Options.Add(rebuildOption);
        command.Options.Add(verboseOption);
        command.SetAction((parseResult, cancellationToken) =>
            runtime.RunRefreshAsync(
                new RefreshCommandOptions(
                    Rebuild: parseResult.GetValue(rebuildOption),
                    Verbose: parseResult.GetValue(verboseOption)),
                cancellationToken));

        return command;
    }
}
