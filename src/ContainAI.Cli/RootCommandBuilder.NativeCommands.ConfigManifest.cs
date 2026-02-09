using System.CommandLine;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli;

internal static partial class MaintenanceCommandsBuilder
{
    internal static Command CreateConfigCommand(ICaiCommandRuntime runtime)
    {
        var command = new Command("config", "Read and write CLI configuration.");
        var globalOption = new Option<bool>("--global", "-g");
        var workspaceOption = new Option<string?>("--workspace");
        var verboseOption = new Option<bool>("--verbose");

        command.Options.Add(globalOption);
        command.Options.Add(workspaceOption);
        command.Options.Add(verboseOption);
        var list = new Command("list");
        list.SetAction((parseResult, cancellationToken) =>
            runtime.RunConfigListAsync(
                new ConfigListCommandOptions(
                    Global: parseResult.GetValue(globalOption),
                    Workspace: parseResult.GetValue(workspaceOption),
                    Verbose: parseResult.GetValue(verboseOption)),
                cancellationToken));

        var get = new Command("get");
        var getKey = new Argument<string>("key");
        get.Arguments.Add(getKey);
        get.SetAction((parseResult, cancellationToken) =>
            runtime.RunConfigGetAsync(
                new ConfigGetCommandOptions(
                    Global: parseResult.GetValue(globalOption),
                    Workspace: parseResult.GetValue(workspaceOption),
                    Verbose: parseResult.GetValue(verboseOption),
                    Key: parseResult.GetValue(getKey)!),
                cancellationToken));

        var set = new Command("set");
        var setKey = new Argument<string>("key");
        var setValue = new Argument<string>("value");
        set.Arguments.Add(setKey);
        set.Arguments.Add(setValue);
        set.SetAction((parseResult, cancellationToken) =>
            runtime.RunConfigSetAsync(
                new ConfigSetCommandOptions(
                    Global: parseResult.GetValue(globalOption),
                    Workspace: parseResult.GetValue(workspaceOption),
                    Verbose: parseResult.GetValue(verboseOption),
                    Key: parseResult.GetValue(setKey)!,
                    Value: parseResult.GetValue(setValue)!),
                cancellationToken));

        var unset = new Command("unset");
        var unsetKey = new Argument<string>("key");
        unset.Arguments.Add(unsetKey);
        unset.SetAction((parseResult, cancellationToken) =>
            runtime.RunConfigUnsetAsync(
                new ConfigUnsetCommandOptions(
                    Global: parseResult.GetValue(globalOption),
                    Workspace: parseResult.GetValue(workspaceOption),
                    Verbose: parseResult.GetValue(verboseOption),
                    Key: parseResult.GetValue(unsetKey)!),
                cancellationToken));

        var resolveVolume = new Command("resolve-volume");
        var explicitVolume = new Argument<string?>("explicit-volume")
        {
            Arity = ArgumentArity.ZeroOrOne,
        };
        resolveVolume.Arguments.Add(explicitVolume);
        resolveVolume.SetAction((parseResult, cancellationToken) =>
            runtime.RunConfigResolveVolumeAsync(
                new ConfigResolveVolumeCommandOptions(
                    Global: parseResult.GetValue(globalOption),
                    Workspace: parseResult.GetValue(workspaceOption),
                    Verbose: parseResult.GetValue(verboseOption),
                    ExplicitVolume: parseResult.GetValue(explicitVolume)),
                cancellationToken));

        command.Subcommands.Add(list);
        command.Subcommands.Add(get);
        command.Subcommands.Add(set);
        command.Subcommands.Add(unset);
        command.Subcommands.Add(resolveVolume);
        return command;
    }

    internal static Command CreateManifestCommand(ICaiCommandRuntime runtime)
    {
        var command = new Command("manifest", "Parse manifests and generate derived artifacts.");

        var parse = new Command("parse");
        var includeDisabledOption = new Option<bool>("--include-disabled");
        var emitSourceFileOption = new Option<bool>("--emit-source-file");
        var parsePathArgument = new Argument<string>("manifest-path");
        parse.Options.Add(includeDisabledOption);
        parse.Options.Add(emitSourceFileOption);
        parse.Arguments.Add(parsePathArgument);
        parse.SetAction((parseResult, cancellationToken) =>
            runtime.RunManifestParseAsync(
                new ManifestParseCommandOptions(
                    IncludeDisabled: parseResult.GetValue(includeDisabledOption),
                    EmitSourceFile: parseResult.GetValue(emitSourceFileOption),
                    ManifestPath: parseResult.GetValue(parsePathArgument)!),
                cancellationToken));

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
            runtime.RunManifestGenerateAsync(
                new ManifestGenerateCommandOptions(
                    Kind: parseResult.GetValue(kindArgument)!,
                    ManifestPath: parseResult.GetValue(generateManifestPathArgument)!,
                    OutputPath: parseResult.GetValue(outputPathArgument)),
                cancellationToken));

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
            runtime.RunManifestApplyAsync(
                new ManifestApplyCommandOptions(
                    Kind: parseResult.GetValue(applyKindArgument)!,
                    ManifestPath: parseResult.GetValue(applyManifestPathArgument)!,
                    DataDir: parseResult.GetValue(dataDirOption),
                    HomeDir: parseResult.GetValue(homeDirOption),
                    ShimDir: parseResult.GetValue(shimDirOption),
                    CaiBinary: parseResult.GetValue(caiBinaryOption)),
                cancellationToken));

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
            var fromOption = parseResult.GetValue(manifestDirOption);
            var fromArgument = parseResult.GetValue(manifestDirArgument);
            return runtime.RunManifestCheckAsync(
                new ManifestCheckCommandOptions(
                    ManifestDir: string.IsNullOrWhiteSpace(fromOption) ? fromArgument : fromOption),
                cancellationToken);
        });

        command.Subcommands.Add(parse);
        command.Subcommands.Add(generate);
        command.Subcommands.Add(apply);
        command.Subcommands.Add(check);
        return command;
    }

    internal static Command CreateTemplateCommand(ICaiCommandRuntime runtime)
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
