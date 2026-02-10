using System.CommandLine;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Commands.Maintenance;

internal static class ImportCommandBuilder
{
    internal static Command Build(ICaiCommandRuntime runtime)
    {
        var command = new Command("import", "Import host configuration into the data volume.");
        var fromOption = new Option<string?>("--from");
        var dataVolumeOption = new Option<string?>("--data-volume");
        var workspaceOption = new Option<string?>("--workspace");
        var configOption = new Option<string?>("--config");
        var dryRunOption = new Option<bool>("--dry-run");
        var noExcludesOption = new Option<bool>("--no-excludes");
        var noSecretsOption = new Option<bool>("--no-secrets");
        var verboseOption = new Option<bool>("--verbose");
        var sourcePathArgument = new Argument<string?>("source-path")
        {
            Arity = ArgumentArity.ZeroOrOne,
            Description = "Import source path (optional positional form).",
        };

        command.Options.Add(fromOption);
        command.Options.Add(dataVolumeOption);
        command.Options.Add(workspaceOption);
        command.Options.Add(configOption);
        command.Options.Add(dryRunOption);
        command.Options.Add(noExcludesOption);
        command.Options.Add(noSecretsOption);
        command.Options.Add(verboseOption);
        command.Arguments.Add(sourcePathArgument);

        command.SetAction((parseResult, cancellationToken) =>
        {
            var sourcePath = parseResult.GetValue(sourcePathArgument);
            var from = parseResult.GetValue(fromOption);
            return runtime.RunImportAsync(
                new ImportCommandOptions(
                    From: from ?? sourcePath,
                    DataVolume: parseResult.GetValue(dataVolumeOption),
                    Workspace: parseResult.GetValue(workspaceOption),
                    Config: parseResult.GetValue(configOption),
                    DryRun: parseResult.GetValue(dryRunOption),
                    NoExcludes: parseResult.GetValue(noExcludesOption),
                    NoSecrets: parseResult.GetValue(noSecretsOption),
                    Verbose: parseResult.GetValue(verboseOption)),
                cancellationToken);
        });

        return command;
    }
}
