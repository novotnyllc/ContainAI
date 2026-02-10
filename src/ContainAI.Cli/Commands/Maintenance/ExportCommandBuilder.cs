using System.CommandLine;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Commands.Maintenance;

internal static class ExportCommandBuilder
{
    internal static Command Build(ICaiCommandRuntime runtime)
    {
        var command = new Command("export", "Export the data volume to a tarball.");
        var outputOption = new Option<string?>("--output", "-o");
        var dataVolumeOption = new Option<string?>("--data-volume");
        var containerOption = new Option<string?>("--container");
        var workspaceOption = new Option<string?>("--workspace");

        command.Options.Add(outputOption);
        command.Options.Add(dataVolumeOption);
        command.Options.Add(containerOption);
        command.Options.Add(workspaceOption);
        command.SetAction((parseResult, cancellationToken) =>
            runtime.RunExportAsync(
                new ExportCommandOptions(
                    Output: parseResult.GetValue(outputOption),
                    DataVolume: parseResult.GetValue(dataVolumeOption),
                    Container: parseResult.GetValue(containerOption),
                    Workspace: parseResult.GetValue(workspaceOption)),
                cancellationToken));

        return command;
    }
}
