using System.CommandLine;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Commands.Maintenance;

internal static class SetupCommandBuilder
{
    internal static Command Build(ICaiCommandRuntime runtime)
    {
        var command = new Command("setup", "Set up local runtime prerequisites.");
        var dryRunOption = new Option<bool>("--dry-run");
        var verboseOption = new Option<bool>("--verbose");
        var skipTemplatesOption = new Option<bool>("--skip-templates");

        command.Options.Add(dryRunOption);
        command.Options.Add(verboseOption);
        command.Options.Add(skipTemplatesOption);
        command.SetAction((parseResult, cancellationToken) =>
            runtime.RunSetupAsync(
                new SetupCommandOptions(
                    DryRun: parseResult.GetValue(dryRunOption),
                    Verbose: parseResult.GetValue(verboseOption),
                    SkipTemplates: parseResult.GetValue(skipTemplatesOption)),
                cancellationToken));

        return command;
    }
}
