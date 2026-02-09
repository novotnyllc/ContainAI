using System.CommandLine;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli;

internal static partial class MaintenanceCommandsBuilder
{
    internal static Command CreateExamplesCommand(ICaiCommandRuntime runtime)
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

    internal static Command CreateImportCommand(ICaiCommandRuntime runtime)
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

    internal static Command CreateExportCommand(ICaiCommandRuntime runtime)
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

    internal static Command CreateSyncCommand(ICaiCommandRuntime runtime)
    {
        var command = new Command("sync", "Run in-container sync operations.");
        command.SetAction((_, cancellationToken) => runtime.RunSyncAsync(cancellationToken));
        return command;
    }

    internal static Command CreateStopCommand(ICaiCommandRuntime runtime)
    {
        var command = new Command("stop", "Stop managed containers.");
        var allOption = new Option<bool>("--all");
        var containerOption = new Option<string?>("--container");
        var removeOption = new Option<bool>("--remove");
        var forceOption = new Option<bool>("--force");
        var exportOption = new Option<bool>("--export");
        var verboseOption = new Option<bool>("--verbose");

        command.Options.Add(allOption);
        command.Options.Add(containerOption);
        command.Options.Add(removeOption);
        command.Options.Add(forceOption);
        command.Options.Add(exportOption);
        command.Options.Add(verboseOption);
        command.SetAction((parseResult, cancellationToken) =>
            runtime.RunStopAsync(
                new StopCommandOptions(
                    All: parseResult.GetValue(allOption),
                    Container: parseResult.GetValue(containerOption),
                    Remove: parseResult.GetValue(removeOption),
                    Force: parseResult.GetValue(forceOption),
                    Export: parseResult.GetValue(exportOption),
                    Verbose: parseResult.GetValue(verboseOption)),
                cancellationToken));

        return command;
    }

    internal static Command CreateGcCommand(ICaiCommandRuntime runtime)
    {
        var command = new Command("gc", "Garbage collect stale resources.");
        var dryRunOption = new Option<bool>("--dry-run");
        var forceOption = new Option<bool>("--force");
        var imagesOption = new Option<bool>("--images");
        var ageOption = new Option<string?>("--age");

        command.Options.Add(dryRunOption);
        command.Options.Add(forceOption);
        command.Options.Add(imagesOption);
        command.Options.Add(ageOption);
        command.SetAction((parseResult, cancellationToken) =>
            runtime.RunGcAsync(
                new GcCommandOptions(
                    DryRun: parseResult.GetValue(dryRunOption),
                    Force: parseResult.GetValue(forceOption),
                    Images: parseResult.GetValue(imagesOption),
                    Age: parseResult.GetValue(ageOption)),
                cancellationToken));

        return command;
    }

    internal static Command CreateSshCommand(ICaiCommandRuntime runtime)
    {
        var command = new Command("ssh", "Manage SSH integration.");

        var cleanup = new Command("cleanup", "Remove stale SSH host configs.");
        var dryRunOption = new Option<bool>("--dry-run");
        cleanup.Options.Add(dryRunOption);
        cleanup.SetAction((parseResult, cancellationToken) =>
            runtime.RunSshCleanupAsync(
                new SshCleanupCommandOptions(
                    DryRun: parseResult.GetValue(dryRunOption)),
                cancellationToken));

        command.Subcommands.Add(cleanup);
        return command;
    }

    internal static Command CreateLinksCommand(ICaiCommandRuntime runtime)
    {
        var command = new Command("links", "Check or repair container symlinks.");

        command.Subcommands.Add(CreateLinksSubcommand("check", runtime));
        command.Subcommands.Add(CreateLinksSubcommand("fix", runtime));
        return command;
    }

    private static Command CreateLinksSubcommand(string name, ICaiCommandRuntime runtime)
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
