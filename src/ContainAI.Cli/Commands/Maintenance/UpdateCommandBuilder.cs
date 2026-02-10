using System.CommandLine;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Commands.Maintenance;

internal static class UpdateCommandBuilder
{
    internal static Command Build(ICaiCommandRuntime runtime)
    {
        var command = new Command("update", "Update the local installation.");
        var dryRunOption = new Option<bool>("--dry-run");
        var stopContainersOption = new Option<bool>("--stop-containers");
        var forceOption = new Option<bool>("--force");
        var limaRecreateOption = new Option<bool>("--lima-recreate");
        var verboseOption = new Option<bool>("--verbose");

        command.Options.Add(dryRunOption);
        command.Options.Add(stopContainersOption);
        command.Options.Add(forceOption);
        command.Options.Add(limaRecreateOption);
        command.Options.Add(verboseOption);
        command.SetAction((parseResult, cancellationToken) =>
            runtime.RunUpdateAsync(
                new UpdateCommandOptions(
                    DryRun: parseResult.GetValue(dryRunOption),
                    StopContainers: parseResult.GetValue(stopContainersOption),
                    Force: parseResult.GetValue(forceOption),
                    LimaRecreate: parseResult.GetValue(limaRecreateOption),
                    Verbose: parseResult.GetValue(verboseOption)),
                cancellationToken));

        return command;
    }
}
