using System.CommandLine;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli;

internal static partial class RootCommandBuilder
{
    private static Command CreateDoctorCommand(ICaiCommandRuntime runtime)
    {
        var command = new Command("doctor", "Check system capabilities and diagnostics.");
        var jsonOption = new Option<bool>("--json");
        var buildTemplatesOption = new Option<bool>("--build-templates");
        var resetLimaOption = new Option<bool>("--reset-lima");

        command.Options.Add(jsonOption);
        command.Options.Add(buildTemplatesOption);
        command.Options.Add(resetLimaOption);
        command.SetAction((parseResult, cancellationToken) =>
        {
            var args = new List<string>();
            AppendFlag(args, "--json", parseResult.GetValue(jsonOption));
            AppendFlag(args, "--build-templates", parseResult.GetValue(buildTemplatesOption));
            AppendFlag(args, "--reset-lima", parseResult.GetValue(resetLimaOption));
            return runtime.RunDoctorAsync(args, cancellationToken);
        });

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
        {
            var args = new List<string>();
            AppendFlag(args, "--all", parseResult.GetValue(allOption));
            AppendFlag(args, "--dry-run", parseResult.GetValue(dryRunOption));
            AppendArgument(args, parseResult.GetValue(targetArgument));
            AppendArgument(args, parseResult.GetValue(targetArgArgument));
            return runtime.RunDoctorFixAsync(args, cancellationToken);
        });

        command.Subcommands.Add(fixCommand);
        return command;
    }

    private static Command CreateValidateCommand(ICaiCommandRuntime runtime)
    {
        var command = new Command("validate", "Validate runtime configuration.");
        var jsonOption = new Option<bool>("--json");
        command.Options.Add(jsonOption);
        command.SetAction((parseResult, cancellationToken) =>
        {
            var args = new List<string>();
            AppendFlag(args, "--json", parseResult.GetValue(jsonOption));
            return runtime.RunValidateAsync(args, cancellationToken);
        });

        return command;
    }

    private static Command CreateSetupCommand(ICaiCommandRuntime runtime)
    {
        var command = new Command("setup", "Set up local runtime prerequisites.");
        var dryRunOption = new Option<bool>("--dry-run");
        var verboseOption = new Option<bool>("--verbose");
        var skipTemplatesOption = new Option<bool>("--skip-templates");

        command.Options.Add(dryRunOption);
        command.Options.Add(verboseOption);
        command.Options.Add(skipTemplatesOption);
        command.SetAction((parseResult, cancellationToken) =>
        {
            var args = new List<string>();
            AppendFlag(args, "--dry-run", parseResult.GetValue(dryRunOption));
            AppendFlag(args, "--verbose", parseResult.GetValue(verboseOption));
            AppendFlag(args, "--skip-templates", parseResult.GetValue(skipTemplatesOption));
            return runtime.RunSetupAsync(args, cancellationToken);
        });

        return command;
    }

    private static Command CreateInstallCommand(ICaiCommandRuntime runtime)
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

    private static Command CreateExamplesCommand(ICaiCommandRuntime runtime)
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

    private static Command CreateImportCommand(ICaiCommandRuntime runtime)
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
            var args = new List<string>();
            var sourcePath = parseResult.GetValue(sourcePathArgument);
            var from = parseResult.GetValue(fromOption);
            AppendOption(args, "--from", from ?? sourcePath);
            AppendOption(args, "--data-volume", parseResult.GetValue(dataVolumeOption));
            AppendOption(args, "--workspace", parseResult.GetValue(workspaceOption));
            AppendOption(args, "--config", parseResult.GetValue(configOption));
            AppendFlag(args, "--dry-run", parseResult.GetValue(dryRunOption));
            AppendFlag(args, "--no-excludes", parseResult.GetValue(noExcludesOption));
            AppendFlag(args, "--no-secrets", parseResult.GetValue(noSecretsOption));
            AppendFlag(args, "--verbose", parseResult.GetValue(verboseOption));
            return runtime.RunImportAsync(args, cancellationToken);
        });

        return command;
    }

    private static Command CreateExportCommand(ICaiCommandRuntime runtime)
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
        {
            var args = new List<string>();
            AppendOption(args, "--output", parseResult.GetValue(outputOption));
            AppendOption(args, "--data-volume", parseResult.GetValue(dataVolumeOption));
            AppendOption(args, "--container", parseResult.GetValue(containerOption));
            AppendOption(args, "--workspace", parseResult.GetValue(workspaceOption));
            return runtime.RunExportAsync(args, cancellationToken);
        });

        return command;
    }

    private static Command CreateSyncCommand(ICaiCommandRuntime runtime)
    {
        var command = new Command("sync", "Run in-container sync operations.");
        command.SetAction((_, cancellationToken) => runtime.RunSyncAsync(cancellationToken));
        return command;
    }

    private static Command CreateStopCommand(ICaiCommandRuntime runtime)
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
        {
            var args = new List<string>();
            AppendFlag(args, "--all", parseResult.GetValue(allOption));
            AppendOption(args, "--container", parseResult.GetValue(containerOption));
            AppendFlag(args, "--remove", parseResult.GetValue(removeOption));
            AppendFlag(args, "--force", parseResult.GetValue(forceOption));
            AppendFlag(args, "--export", parseResult.GetValue(exportOption));
            AppendFlag(args, "--verbose", parseResult.GetValue(verboseOption));
            return runtime.RunStopAsync(args, cancellationToken);
        });

        return command;
    }

    private static Command CreateGcCommand(ICaiCommandRuntime runtime)
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
        {
            var args = new List<string>();
            AppendFlag(args, "--dry-run", parseResult.GetValue(dryRunOption));
            AppendFlag(args, "--force", parseResult.GetValue(forceOption));
            AppendFlag(args, "--images", parseResult.GetValue(imagesOption));
            AppendOption(args, "--age", parseResult.GetValue(ageOption));
            return runtime.RunGcAsync(args, cancellationToken);
        });

        return command;
    }

    private static Command CreateSshCommand(ICaiCommandRuntime runtime)
    {
        var command = new Command("ssh", "Manage SSH integration.");
        command.SetAction((_, cancellationToken) => runtime.RunSshAsync(cancellationToken));

        var cleanup = new Command("cleanup", "Remove stale SSH host configs.");
        var dryRunOption = new Option<bool>("--dry-run");
        cleanup.Options.Add(dryRunOption);
        cleanup.SetAction((parseResult, cancellationToken) =>
        {
            var args = new List<string>();
            AppendFlag(args, "--dry-run", parseResult.GetValue(dryRunOption));
            return runtime.RunSshCleanupAsync(args, cancellationToken);
        });

        command.Subcommands.Add(cleanup);
        return command;
    }

    private static Command CreateLinksCommand(ICaiCommandRuntime runtime)
    {
        var command = new Command("links", "Check or repair container symlinks.");
        command.SetAction((_, cancellationToken) => runtime.RunLinksAsync(cancellationToken));

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
            var args = new List<string>();
            AppendOption(args, "--name", parseResult.GetValue(nameOption));
            AppendOption(args, "--container", parseResult.GetValue(containerOption));
            AppendOption(args, "--workspace", parseResult.GetValue(workspaceOption) ?? parseResult.GetValue(workspaceArgument));
            AppendFlag(args, "--dry-run", parseResult.GetValue(dryRunOption));
            AppendFlag(args, "--quiet", parseResult.GetValue(quietOption));
            AppendFlag(args, "--verbose", parseResult.GetValue(verboseOption));
            AppendOption(args, "--config", parseResult.GetValue(configOption));
            return name == "check"
                ? runtime.RunLinksCheckAsync(args, cancellationToken)
                : runtime.RunLinksFixAsync(args, cancellationToken);
        });

        return command;
    }

    private static Command CreateConfigCommand(ICaiCommandRuntime runtime)
    {
        var command = new Command("config", "Read and write CLI configuration.");
        var globalOption = new Option<bool>("--global", "-g");
        var workspaceOption = new Option<string?>("--workspace");
        var verboseOption = new Option<bool>("--verbose");

        command.Options.Add(globalOption);
        command.Options.Add(workspaceOption);
        command.Options.Add(verboseOption);
        command.SetAction((_, cancellationToken) => runtime.RunConfigAsync(cancellationToken));

        var list = new Command("list");
        list.SetAction((parseResult, cancellationToken) => runtime.RunConfigListAsync(
            BuildConfigArgs("list", parseResult, globalOption, workspaceOption, verboseOption),
            cancellationToken));

        var get = new Command("get");
        var getKey = new Argument<string>("key");
        get.Arguments.Add(getKey);
        get.SetAction((parseResult, cancellationToken) =>
        {
            var args = BuildConfigArgs("get", parseResult, globalOption, workspaceOption, verboseOption);
            args.Add(parseResult.GetValue(getKey)!);
            return runtime.RunConfigGetAsync(args, cancellationToken);
        });

        var set = new Command("set");
        var setKey = new Argument<string>("key");
        var setValue = new Argument<string>("value");
        set.Arguments.Add(setKey);
        set.Arguments.Add(setValue);
        set.SetAction((parseResult, cancellationToken) =>
        {
            var args = BuildConfigArgs("set", parseResult, globalOption, workspaceOption, verboseOption);
            args.Add(parseResult.GetValue(setKey)!);
            args.Add(parseResult.GetValue(setValue)!);
            return runtime.RunConfigSetAsync(args, cancellationToken);
        });

        var unset = new Command("unset");
        var unsetKey = new Argument<string>("key");
        unset.Arguments.Add(unsetKey);
        unset.SetAction((parseResult, cancellationToken) =>
        {
            var args = BuildConfigArgs("unset", parseResult, globalOption, workspaceOption, verboseOption);
            args.Add(parseResult.GetValue(unsetKey)!);
            return runtime.RunConfigUnsetAsync(args, cancellationToken);
        });

        var resolveVolume = new Command("resolve-volume");
        var explicitVolume = new Argument<string?>("explicit-volume")
        {
            Arity = ArgumentArity.ZeroOrOne,
        };
        resolveVolume.Arguments.Add(explicitVolume);
        resolveVolume.SetAction((parseResult, cancellationToken) =>
        {
            var args = BuildConfigArgs("resolve-volume", parseResult, globalOption, workspaceOption, verboseOption);
            AppendArgument(args, parseResult.GetValue(explicitVolume));
            return runtime.RunConfigResolveVolumeAsync(args, cancellationToken);
        });

        command.Subcommands.Add(list);
        command.Subcommands.Add(get);
        command.Subcommands.Add(set);
        command.Subcommands.Add(unset);
        command.Subcommands.Add(resolveVolume);
        return command;
    }

    private static List<string> BuildConfigArgs(
        string action,
        ParseResult parseResult,
        Option<bool> globalOption,
        Option<string?> workspaceOption,
        Option<bool> verboseOption)
    {
        var args = new List<string>();
        AppendFlag(args, "--global", parseResult.GetValue(globalOption));
        AppendOption(args, "--workspace", parseResult.GetValue(workspaceOption));
        AppendFlag(args, "--verbose", parseResult.GetValue(verboseOption));
        args.Add(action);
        return args;
    }

    private static Command CreateManifestCommand(ICaiCommandRuntime runtime)
    {
        var command = new Command("manifest", "Parse manifests and generate derived artifacts.");
        command.SetAction((_, cancellationToken) => runtime.RunManifestAsync(cancellationToken));

        var parse = new Command("parse");
        var includeDisabledOption = new Option<bool>("--include-disabled");
        var emitSourceFileOption = new Option<bool>("--emit-source-file");
        var parsePathArgument = new Argument<string>("manifest-path");
        parse.Options.Add(includeDisabledOption);
        parse.Options.Add(emitSourceFileOption);
        parse.Arguments.Add(parsePathArgument);
        parse.SetAction((parseResult, cancellationToken) =>
        {
            var args = new List<string>();
            AppendFlag(args, "--include-disabled", parseResult.GetValue(includeDisabledOption));
            AppendFlag(args, "--emit-source-file", parseResult.GetValue(emitSourceFileOption));
            args.Add(parseResult.GetValue(parsePathArgument)!);
            return runtime.RunManifestParseAsync(args, cancellationToken);
        });

        var generate = new Command("generate");
        var kindArgument = new Argument<string>("kind");
        kindArgument.AcceptOnlyFromAmong("container-link-spec");
        var generateManifestPathArgument = new Argument<string>("manifest-path");
        var outputPathArgument = new Argument<string?>("output-path")
        {
            Arity = ArgumentArity.ZeroOrOne,
        };
        generate.Arguments.Add(kindArgument);
        generate.Arguments.Add(generateManifestPathArgument);
        generate.Arguments.Add(outputPathArgument);
        generate.SetAction((parseResult, cancellationToken) =>
        {
            var args = new List<string>
            {
                parseResult.GetValue(kindArgument)!,
                parseResult.GetValue(generateManifestPathArgument)!,
            };
            AppendArgument(args, parseResult.GetValue(outputPathArgument));
            return runtime.RunManifestGenerateAsync(args, cancellationToken);
        });

        var apply = new Command("apply");
        var applyKindArgument = new Argument<string>("kind");
        applyKindArgument.AcceptOnlyFromAmong("container-links", "init-dirs", "agent-shims");
        var applyManifestPathArgument = new Argument<string>("manifest-path");
        var dataDirOption = new Option<string?>("--data-dir");
        var homeDirOption = new Option<string?>("--home-dir");
        var shimDirOption = new Option<string?>("--shim-dir");
        var caiBinaryOption = new Option<string?>("--cai-binary");
        apply.Arguments.Add(applyKindArgument);
        apply.Arguments.Add(applyManifestPathArgument);
        apply.Options.Add(dataDirOption);
        apply.Options.Add(homeDirOption);
        apply.Options.Add(shimDirOption);
        apply.Options.Add(caiBinaryOption);
        apply.SetAction((parseResult, cancellationToken) =>
        {
            var args = new List<string>
            {
                parseResult.GetValue(applyKindArgument)!,
                parseResult.GetValue(applyManifestPathArgument)!,
            };
            AppendOption(args, "--data-dir", parseResult.GetValue(dataDirOption));
            AppendOption(args, "--home-dir", parseResult.GetValue(homeDirOption));
            AppendOption(args, "--shim-dir", parseResult.GetValue(shimDirOption));
            AppendOption(args, "--cai-binary", parseResult.GetValue(caiBinaryOption));
            return runtime.RunManifestApplyAsync(args, cancellationToken);
        });

        var check = new Command("check");
        var manifestDirOption = new Option<string?>("--manifest-dir");
        var manifestDirArgument = new Argument<string?>("manifest-dir")
        {
            Arity = ArgumentArity.ZeroOrOne,
        };
        check.Options.Add(manifestDirOption);
        check.Arguments.Add(manifestDirArgument);
        check.Validators.Add(result =>
        {
            var fromOption = result.GetValue(manifestDirOption);
            var fromArgument = result.GetValue(manifestDirArgument);
            if (!string.IsNullOrWhiteSpace(fromOption) && !string.IsNullOrWhiteSpace(fromArgument))
            {
                result.AddError("Choose either --manifest-dir or manifest-dir argument.");
            }
        });
        check.SetAction((parseResult, cancellationToken) =>
        {
            var args = new List<string>();
            var fromOption = parseResult.GetValue(manifestDirOption);
            var fromArgument = parseResult.GetValue(manifestDirArgument);
            AppendOption(args, "--manifest-dir", fromOption);
            if (string.IsNullOrWhiteSpace(fromOption))
            {
                AppendArgument(args, fromArgument);
            }

            return runtime.RunManifestCheckAsync(args, cancellationToken);
        });

        command.Subcommands.Add(parse);
        command.Subcommands.Add(generate);
        command.Subcommands.Add(apply);
        command.Subcommands.Add(check);
        return command;
    }

    private static Command CreateTemplateCommand(ICaiCommandRuntime runtime)
    {
        var command = new Command("template", "Manage templates.");
        command.SetAction((_, cancellationToken) => runtime.RunTemplateAsync(cancellationToken));

        var upgrade = new Command("upgrade");
        var templateName = new Argument<string?>("name")
        {
            Arity = ArgumentArity.ZeroOrOne,
        };
        var dryRunOption = new Option<bool>("--dry-run");
        upgrade.Arguments.Add(templateName);
        upgrade.Options.Add(dryRunOption);
        upgrade.SetAction((parseResult, cancellationToken) =>
        {
            var args = new List<string>();
            AppendArgument(args, parseResult.GetValue(templateName));
            AppendFlag(args, "--dry-run", parseResult.GetValue(dryRunOption));
            return runtime.RunTemplateUpgradeAsync(args, cancellationToken);
        });

        command.Subcommands.Add(upgrade);
        return command;
    }

    private static Command CreateUpdateCommand(ICaiCommandRuntime runtime)
    {
        var command = new Command("update", "Update the local installation.");
        var dryRunOption = new Option<bool>("--dry-run");
        var stopContainersOption = new Option<bool>("--stop-containers");
        var forceOption = new Option<bool>("--force");
        var limaRecreateOption = new Option<bool>("--lima-recreate");
        var verboseOption = new Option<bool>("--verbose");

        command.Options.Add(dryRunOption);
        command.Options.Add(stopContainersOption);
        command.Options.Add(forceOption);
        command.Options.Add(limaRecreateOption);
        command.Options.Add(verboseOption);
        command.SetAction((parseResult, cancellationToken) =>
        {
            var args = new List<string>();
            AppendFlag(args, "--dry-run", parseResult.GetValue(dryRunOption));
            AppendFlag(args, "--stop-containers", parseResult.GetValue(stopContainersOption));
            AppendFlag(args, "--force", parseResult.GetValue(forceOption));
            AppendFlag(args, "--lima-recreate", parseResult.GetValue(limaRecreateOption));
            AppendFlag(args, "--verbose", parseResult.GetValue(verboseOption));
            return runtime.RunUpdateAsync(args, cancellationToken);
        });

        return command;
    }

    private static Command CreateRefreshCommand(ICaiCommandRuntime runtime)
    {
        var command = new Command("refresh", "Refresh images and rebuild templates when requested.");
        var rebuildOption = new Option<bool>("--rebuild");
        var verboseOption = new Option<bool>("--verbose");

        command.Options.Add(rebuildOption);
        command.Options.Add(verboseOption);
        command.SetAction((parseResult, cancellationToken) =>
        {
            var args = new List<string>();
            AppendFlag(args, "--rebuild", parseResult.GetValue(rebuildOption));
            AppendFlag(args, "--verbose", parseResult.GetValue(verboseOption));
            return runtime.RunRefreshAsync(args, cancellationToken);
        });

        return command;
    }

    private static Command CreateUninstallCommand(ICaiCommandRuntime runtime)
    {
        var command = new Command("uninstall", "Remove local installation artifacts.");
        var dryRunOption = new Option<bool>("--dry-run");
        var containersOption = new Option<bool>("--containers");
        var volumesOption = new Option<bool>("--volumes");
        var forceOption = new Option<bool>("--force");
        var verboseOption = new Option<bool>("--verbose");

        command.Options.Add(dryRunOption);
        command.Options.Add(containersOption);
        command.Options.Add(volumesOption);
        command.Options.Add(forceOption);
        command.Options.Add(verboseOption);
        command.SetAction((parseResult, cancellationToken) =>
        {
            var args = new List<string>();
            AppendFlag(args, "--dry-run", parseResult.GetValue(dryRunOption));
            AppendFlag(args, "--containers", parseResult.GetValue(containersOption));
            AppendFlag(args, "--volumes", parseResult.GetValue(volumesOption));
            AppendFlag(args, "--force", parseResult.GetValue(forceOption));
            AppendFlag(args, "--verbose", parseResult.GetValue(verboseOption));
            return runtime.RunUninstallAsync(args, cancellationToken);
        });

        return command;
    }

    private static Command CreateHelpCommand(ICaiCommandRuntime runtime)
    {
        var command = new Command("help", "Show help.");
        var topic = new Argument<string?>("topic")
        {
            Arity = ArgumentArity.ZeroOrOne,
        };

        command.Arguments.Add(topic);
        command.SetAction((parseResult, cancellationToken) =>
        {
            var args = new List<string>();
            AppendArgument(args, parseResult.GetValue(topic));
            return runtime.RunHelpAsync(args, cancellationToken);
        });

        return command;
    }

    private static Command CreateSystemCommand(ICaiCommandRuntime runtime)
    {
        var command = new Command("system", "Container-internal runtime commands.");
        command.SetAction((_, cancellationToken) => runtime.RunSystemAsync(cancellationToken));

        var init = new Command("init");
        var dataDirOption = new Option<string?>("--data-dir");
        var homeDirOption = new Option<string?>("--home-dir");
        var manifestsDirOption = new Option<string?>("--manifests-dir");
        var templateHooksOption = new Option<string?>("--template-hooks");
        var workspaceHooksOption = new Option<string?>("--workspace-hooks");
        var workspaceDirOption = new Option<string?>("--workspace-dir");
        var quietOption = new Option<bool>("--quiet");
        init.Options.Add(dataDirOption);
        init.Options.Add(homeDirOption);
        init.Options.Add(manifestsDirOption);
        init.Options.Add(templateHooksOption);
        init.Options.Add(workspaceHooksOption);
        init.Options.Add(workspaceDirOption);
        init.Options.Add(quietOption);
        init.SetAction((parseResult, cancellationToken) =>
        {
            var args = new List<string>();
            AppendOption(args, "--data-dir", parseResult.GetValue(dataDirOption));
            AppendOption(args, "--home-dir", parseResult.GetValue(homeDirOption));
            AppendOption(args, "--manifests-dir", parseResult.GetValue(manifestsDirOption));
            AppendOption(args, "--template-hooks", parseResult.GetValue(templateHooksOption));
            AppendOption(args, "--workspace-hooks", parseResult.GetValue(workspaceHooksOption));
            AppendOption(args, "--workspace-dir", parseResult.GetValue(workspaceDirOption));
            AppendFlag(args, "--quiet", parseResult.GetValue(quietOption));
            return runtime.RunSystemInitAsync(args, cancellationToken);
        });

        var linkRepair = new Command("link-repair");
        var checkOption = new Option<bool>("--check");
        var fixOption = new Option<bool>("--fix");
        var dryRunOption = new Option<bool>("--dry-run");
        var linkQuietOption = new Option<bool>("--quiet");
        var builtinSpecOption = new Option<string?>("--builtin-spec");
        var userSpecOption = new Option<string?>("--user-spec");
        var checkedAtFileOption = new Option<string?>("--checked-at-file");
        linkRepair.Options.Add(checkOption);
        linkRepair.Options.Add(fixOption);
        linkRepair.Options.Add(dryRunOption);
        linkRepair.Options.Add(linkQuietOption);
        linkRepair.Options.Add(builtinSpecOption);
        linkRepair.Options.Add(userSpecOption);
        linkRepair.Options.Add(checkedAtFileOption);
        linkRepair.SetAction((parseResult, cancellationToken) =>
        {
            var args = new List<string>();
            AppendFlag(args, "--check", parseResult.GetValue(checkOption));
            AppendFlag(args, "--fix", parseResult.GetValue(fixOption));
            AppendFlag(args, "--dry-run", parseResult.GetValue(dryRunOption));
            AppendFlag(args, "--quiet", parseResult.GetValue(linkQuietOption));
            AppendOption(args, "--builtin-spec", parseResult.GetValue(builtinSpecOption));
            AppendOption(args, "--user-spec", parseResult.GetValue(userSpecOption));
            AppendOption(args, "--checked-at-file", parseResult.GetValue(checkedAtFileOption));
            return runtime.RunSystemLinkRepairAsync(args, cancellationToken);
        });

        var watchLinks = new Command("watch-links");
        var pollIntervalOption = new Option<string?>("--poll-interval");
        var importedAtFileOption = new Option<string?>("--imported-at-file");
        var watchCheckedAtFileOption = new Option<string?>("--checked-at-file");
        var watchQuietOption = new Option<bool>("--quiet");
        watchLinks.Options.Add(pollIntervalOption);
        watchLinks.Options.Add(importedAtFileOption);
        watchLinks.Options.Add(watchCheckedAtFileOption);
        watchLinks.Options.Add(watchQuietOption);
        watchLinks.SetAction((parseResult, cancellationToken) =>
        {
            var args = new List<string>();
            AppendOption(args, "--poll-interval", parseResult.GetValue(pollIntervalOption));
            AppendOption(args, "--imported-at-file", parseResult.GetValue(importedAtFileOption));
            AppendOption(args, "--checked-at-file", parseResult.GetValue(watchCheckedAtFileOption));
            AppendFlag(args, "--quiet", parseResult.GetValue(watchQuietOption));
            return runtime.RunSystemWatchLinksAsync(args, cancellationToken);
        });

        var devcontainer = new Command("devcontainer");
        devcontainer.SetAction((_, cancellationToken) => runtime.RunSystemDevcontainerAsync(cancellationToken));

        var install = new Command("install");
        var featureDirOption = new Option<string?>("--feature-dir");
        install.Options.Add(featureDirOption);
        install.SetAction((parseResult, cancellationToken) =>
        {
            var args = new List<string>();
            AppendOption(args, "--feature-dir", parseResult.GetValue(featureDirOption));
            return runtime.RunSystemDevcontainerInstallAsync(args, cancellationToken);
        });

        var initDevcontainer = new Command("init");
        initDevcontainer.SetAction((_, cancellationToken) => runtime.RunSystemDevcontainerInitAsync(cancellationToken));

        var startDevcontainer = new Command("start");
        startDevcontainer.SetAction((_, cancellationToken) => runtime.RunSystemDevcontainerStartAsync(cancellationToken));

        var verifySysbox = new Command("verify-sysbox");
        verifySysbox.SetAction((_, cancellationToken) => runtime.RunSystemDevcontainerVerifySysboxAsync(cancellationToken));

        devcontainer.Subcommands.Add(install);
        devcontainer.Subcommands.Add(initDevcontainer);
        devcontainer.Subcommands.Add(startDevcontainer);
        devcontainer.Subcommands.Add(verifySysbox);

        command.Subcommands.Add(init);
        command.Subcommands.Add(linkRepair);
        command.Subcommands.Add(watchLinks);
        command.Subcommands.Add(devcontainer);
        return command;
    }

    private static void AppendFlag(List<string> args, string option, bool enabled)
    {
        if (enabled)
        {
            args.Add(option);
        }
    }

    private static void AppendOption(List<string> args, string option, string? value)
    {
        if (!string.IsNullOrWhiteSpace(value))
        {
            args.Add(option);
            args.Add(value);
        }
    }

    private static void AppendArgument(List<string> args, string? value)
    {
        if (!string.IsNullOrWhiteSpace(value))
        {
            args.Add(value);
        }
    }
}
