using System.CommandLine;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Commands.Maintenance;

internal static class LinksCommandBuilder
{
    internal static Command Build(ICaiCommandRuntime runtime)
    {
        var command = new Command("links", "Check or repair container symlinks.");

        command.Subcommands.Add(CreateSubcommand("check", runtime));
        command.Subcommands.Add(CreateSubcommand("fix", runtime));
        return command;
    }

    private static Command CreateSubcommand(string name, ICaiCommandRuntime runtime)
    {
        var command = new Command(name);
        var nameOption = new Option<string?>("--name");
        var containerOption = new Option<string?>("--container");
        var workspaceOption = new Option<string?>("--workspace");
        var workspaceArgument = new Argument<string?>("workspace")
        {
            Arity = ArgumentArity.ZeroOrOne,
            Description = "Workspace path (optional positional form).",
        };
        var dryRunOption = new Option<bool>("--dry-run");
        var quietOption = new Option<bool>("--quiet", "-q");
        var verboseOption = new Option<bool>("--verbose");
        var configOption = new Option<string?>("--config");

        command.Options.Add(nameOption);
        command.Options.Add(containerOption);
        command.Options.Add(workspaceOption);
        command.Options.Add(dryRunOption);
        command.Options.Add(quietOption);
        command.Options.Add(verboseOption);
        command.Options.Add(configOption);
        command.Arguments.Add(workspaceArgument);

        command.SetAction((parseResult, cancellationToken) =>
        {
            var options = new LinksSubcommandOptions(
                Name: parseResult.GetValue(nameOption),
                Container: parseResult.GetValue(containerOption),
                Workspace: parseResult.GetValue(workspaceOption) ?? parseResult.GetValue(workspaceArgument),
                DryRun: parseResult.GetValue(dryRunOption),
                Quiet: parseResult.GetValue(quietOption),
                Verbose: parseResult.GetValue(verboseOption),
                Config: parseResult.GetValue(configOption));
            return name == "check"
                ? runtime.RunLinksCheckAsync(options, cancellationToken)
                : runtime.RunLinksFixAsync(options, cancellationToken);
        });

        return command;
    }
}
