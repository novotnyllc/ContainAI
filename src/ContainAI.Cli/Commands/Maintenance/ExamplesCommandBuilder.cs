using System.CommandLine;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Commands.Maintenance;

internal static class ExamplesCommandBuilder
{
    internal static Command Build(ICaiCommandRuntime runtime)
    {
        var command = new Command("examples", "List or export sample TOML configuration files.");
        command.SetAction((_, cancellationToken) => runtime.RunExamplesListAsync(cancellationToken));

        var list = new Command("list", "List available sample files.");
        list.SetAction((_, cancellationToken) => runtime.RunExamplesListAsync(cancellationToken));

        var export = new Command("export", "Write sample TOML files to a target directory.");
        var outputDirOption = new Option<string?>("--output-dir", "-o")
        {
            Description = "Directory where sample TOML files will be written.",
            Required = true,
        };
        var forceOption = new Option<bool>("--force")
        {
            Description = "Overwrite existing files in the output directory.",
        };
        export.Options.Add(outputDirOption);
        export.Options.Add(forceOption);
        export.SetAction((parseResult, cancellationToken) =>
        {
            var outputDir = parseResult.GetValue(outputDirOption);
            if (string.IsNullOrWhiteSpace(outputDir))
            {
                throw new InvalidOperationException("--output-dir is required.");
            }

            return runtime.RunExamplesExportAsync(
                new ExamplesExportCommandOptions(
                    OutputDir: outputDir,
                    Force: parseResult.GetValue(forceOption)),
                cancellationToken);
        });

        command.Subcommands.Add(list);
        command.Subcommands.Add(export);
        return command;
    }
}
