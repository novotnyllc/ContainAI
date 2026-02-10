using System.CommandLine;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Commands.Maintenance;

internal static class DoctorCommandBuilder
{
    internal static Command Build(ICaiCommandRuntime runtime)
    {
        var command = new Command("doctor", "Check system capabilities and diagnostics.");
        var jsonOption = new Option<bool>("--json");
        var buildTemplatesOption = new Option<bool>("--build-templates");
        var resetLimaOption = new Option<bool>("--reset-lima");

        command.Options.Add(jsonOption);
        command.Options.Add(buildTemplatesOption);
        command.Options.Add(resetLimaOption);
        command.SetAction((parseResult, cancellationToken) =>
            runtime.RunDoctorAsync(
                new DoctorCommandOptions(
                    Json: parseResult.GetValue(jsonOption),
                    BuildTemplates: parseResult.GetValue(buildTemplatesOption),
                    ResetLima: parseResult.GetValue(resetLimaOption)),
                cancellationToken));

        var fixCommand = new Command("fix", "Run doctor remediation routines.");
        var allOption = new Option<bool>("--all");
        var dryRunOption = new Option<bool>("--dry-run");
        var targetArgument = new Argument<string>("target")
        {
            Arity = ArgumentArity.ZeroOrOne,
        };
        targetArgument.AcceptOnlyFromAmong("container", "template");
        var targetArgArgument = new Argument<string>("target-arg")
        {
            Arity = ArgumentArity.ZeroOrOne,
        };

        fixCommand.Options.Add(allOption);
        fixCommand.Options.Add(dryRunOption);
        fixCommand.Arguments.Add(targetArgument);
        fixCommand.Arguments.Add(targetArgArgument);
        fixCommand.Validators.Add(result =>
        {
            var target = result.GetValue(targetArgument);
            var targetArg = result.GetValue(targetArgArgument);
            var includeAll = result.GetValue(allOption);
            var hasTarget = !string.IsNullOrWhiteSpace(target);
            var hasTargetArg = !string.IsNullOrWhiteSpace(targetArg);

            if (hasTarget && target is not ("container" or "template"))
            {
                result.AddError("target must be 'container' or 'template'.");
            }

            if (includeAll && (hasTarget || hasTargetArg))
            {
                result.AddError("--all cannot be combined with target or target-arg.");
            }

            if (!hasTarget && hasTargetArg)
            {
                result.AddError("target-arg requires target.");
            }
        });
        fixCommand.SetAction((parseResult, cancellationToken) =>
            runtime.RunDoctorFixAsync(
                new DoctorFixCommandOptions(
                    All: parseResult.GetValue(allOption),
                    DryRun: parseResult.GetValue(dryRunOption),
                    Target: parseResult.GetValue(targetArgument),
                    TargetArg: parseResult.GetValue(targetArgArgument)),
                cancellationToken));

        command.Subcommands.Add(fixCommand);
        return command;
    }
}
