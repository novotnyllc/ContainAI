using System.CommandLine;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli;

internal static partial class MaintenanceCommandsBuilder
{
    internal static Command CreateDoctorCommand(ICaiCommandRuntime runtime)
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

    internal static Command CreateValidateCommand(ICaiCommandRuntime runtime)
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

    internal static Command CreateSetupCommand(ICaiCommandRuntime runtime)
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

    internal static Command CreateInstallCommand(ICaiCommandRuntime runtime)
    {
        var command = new Command("install", "Install ContainAI into local user directories.");
        var localOption = new Option<bool>("--local")
        {
            Description = "Require local install payload resolution.",
        };
        var yesOption = new Option<bool>("--yes")
        {
            Description = "Auto-confirm installer actions.",
        };
        var noSetupOption = new Option<bool>("--no-setup")
        {
            Description = "Skip automatic setup/update after install.",
        };
        var installDirOption = new Option<string?>("--install-dir")
        {
            Description = "Installation directory (overrides CAI_INSTALL_DIR).",
        };
        var binDirOption = new Option<string?>("--bin-dir")
        {
            Description = "Wrapper binary directory (overrides CAI_BIN_DIR).",
        };
        var channelOption = new Option<string?>("--channel")
        {
            Description = "Optional installer channel hint.",
        };
        channelOption.AcceptOnlyFromAmong("stable", "nightly");
        var verboseOption = new Option<bool>("--verbose")
        {
            Description = "Enable verbose installer logging.",
        };

        command.Options.Add(localOption);
        command.Options.Add(yesOption);
        command.Options.Add(noSetupOption);
        command.Options.Add(installDirOption);
        command.Options.Add(binDirOption);
        command.Options.Add(channelOption);
        command.Options.Add(verboseOption);

        command.SetAction((parseResult, cancellationToken) =>
            runtime.RunInstallAsync(
                new InstallCommandOptions(
                    Local: parseResult.GetValue(localOption),
                    Yes: parseResult.GetValue(yesOption),
                    NoSetup: parseResult.GetValue(noSetupOption),
                    InstallDir: parseResult.GetValue(installDirOption),
                    BinDir: parseResult.GetValue(binDirOption),
                    Channel: parseResult.GetValue(channelOption),
                    Verbose: parseResult.GetValue(verboseOption)),
                cancellationToken));

        return command;
    }
}
