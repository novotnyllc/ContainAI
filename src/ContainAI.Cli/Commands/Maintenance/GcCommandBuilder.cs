using System.CommandLine;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Commands.Maintenance;

internal static class GcCommandBuilder
{
    internal static Command Build(ICaiCommandRuntime runtime)
    {
        var command = new Command("gc", "Garbage collect stale resources.");
        var dryRunOption = new Option<bool>("--dry-run");
        var forceOption = new Option<bool>("--force");
        var imagesOption = new Option<bool>("--images");
        var ageOption = new Option<string?>("--age");

        command.Options.Add(dryRunOption);
        command.Options.Add(forceOption);
        command.Options.Add(imagesOption);
        command.Options.Add(ageOption);
        command.SetAction((parseResult, cancellationToken) =>
            runtime.RunGcAsync(
                new GcCommandOptions(
                    DryRun: parseResult.GetValue(dryRunOption),
                    Force: parseResult.GetValue(forceOption),
                    Images: parseResult.GetValue(imagesOption),
                    Age: parseResult.GetValue(ageOption)),
                cancellationToken));

        return command;
    }
}
