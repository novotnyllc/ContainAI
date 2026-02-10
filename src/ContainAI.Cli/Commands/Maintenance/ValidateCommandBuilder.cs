using System.CommandLine;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Commands.Maintenance;

internal static class ValidateCommandBuilder
{
    internal static Command Build(ICaiCommandRuntime runtime)
    {
        var command = new Command("validate", "Validate runtime configuration.");
        var jsonOption = new Option<bool>("--json");
        command.Options.Add(jsonOption);
        command.SetAction((parseResult, cancellationToken) =>
            runtime.RunValidateAsync(
                new ValidateCommandOptions(
                    Json: parseResult.GetValue(jsonOption)),
                cancellationToken));

        return command;
    }
}
