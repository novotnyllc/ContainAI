using System.CommandLine;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Commands.Maintenance;

internal static class UninstallCommandBuilder
{
    internal static Command Build(ICaiCommandRuntime runtime)
    {
        var command = new Command("uninstall", "Remove local installation artifacts.");
        var dryRunOption = new Option<bool>("--dry-run");
        var containersOption = new Option<bool>("--containers");
        var volumesOption = new Option<bool>("--volumes");
        var forceOption = new Option<bool>("--force");
        var verboseOption = new Option<bool>("--verbose");

        command.Options.Add(dryRunOption);
        command.Options.Add(containersOption);
        command.Options.Add(volumesOption);
        command.Options.Add(forceOption);
        command.Options.Add(verboseOption);
        command.SetAction((parseResult, cancellationToken) =>
            runtime.RunUninstallAsync(
                new UninstallCommandOptions(
                    DryRun: parseResult.GetValue(dryRunOption),
                    Containers: parseResult.GetValue(containersOption),
                    Volumes: parseResult.GetValue(volumesOption),
                    Force: parseResult.GetValue(forceOption),
                    Verbose: parseResult.GetValue(verboseOption)),
                cancellationToken));

        return command;
    }
}
