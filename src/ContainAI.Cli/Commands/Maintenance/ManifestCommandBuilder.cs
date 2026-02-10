using System.CommandLine;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Commands.Maintenance;

internal static class ManifestCommandBuilder
{
    internal static Command Build(ICaiCommandRuntime runtime)
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
}
