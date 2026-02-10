using System.CommandLine;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Commands.Maintenance;

internal static class ConfigCommandBuilder
{
    internal static Command Build(ICaiCommandRuntime runtime)
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
}
