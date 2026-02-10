using System.CommandLine;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Commands.Maintenance;

internal static class TemplateCommandBuilder
{
    internal static Command Build(ICaiCommandRuntime runtime)
    {
        var command = new Command("template", "Manage templates.");

        var upgrade = new Command("upgrade");
        var templateName = new Argument<string?>("name")
        {
            Arity = ArgumentArity.ZeroOrOne,
        };
        var dryRunOption = new Option<bool>("--dry-run");
        upgrade.Arguments.Add(templateName);
        upgrade.Options.Add(dryRunOption);
        upgrade.SetAction((parseResult, cancellationToken) =>
            runtime.RunTemplateUpgradeAsync(
                new TemplateUpgradeCommandOptions(
                    Name: parseResult.GetValue(templateName),
                    DryRun: parseResult.GetValue(dryRunOption)),
                cancellationToken));

        command.Subcommands.Add(upgrade);
        return command;
    }
}
