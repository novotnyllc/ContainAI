using System.CommandLine;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli;

internal static partial class MaintenanceCommandsBuilder
{
    internal static Command CreateUpdateCommand(ICaiCommandRuntime runtime)
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
            runtime.RunUpdateAsync(
                new UpdateCommandOptions(
                    DryRun: parseResult.GetValue(dryRunOption),
                    StopContainers: parseResult.GetValue(stopContainersOption),
                    Force: parseResult.GetValue(forceOption),
                    LimaRecreate: parseResult.GetValue(limaRecreateOption),
                    Verbose: parseResult.GetValue(verboseOption)),
                cancellationToken));

        return command;
    }

    internal static Command CreateRefreshCommand(ICaiCommandRuntime runtime)
    {
        var command = new Command("refresh", "Refresh images and rebuild templates when requested.");
        var rebuildOption = new Option<bool>("--rebuild");
        var verboseOption = new Option<bool>("--verbose");

        command.Options.Add(rebuildOption);
        command.Options.Add(verboseOption);
        command.SetAction((parseResult, cancellationToken) =>
            runtime.RunRefreshAsync(
                new RefreshCommandOptions(
                    Rebuild: parseResult.GetValue(rebuildOption),
                    Verbose: parseResult.GetValue(verboseOption)),
                cancellationToken));

        return command;
    }

    internal static Command CreateUninstallCommand(ICaiCommandRuntime runtime)
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
            runtime.RunUninstallAsync(
                new UninstallCommandOptions(
                    DryRun: parseResult.GetValue(dryRunOption),
                    Containers: parseResult.GetValue(containersOption),
                    Volumes: parseResult.GetValue(volumesOption),
                    Force: parseResult.GetValue(forceOption),
                    Verbose: parseResult.GetValue(verboseOption)),
                cancellationToken));

        return command;
    }

    internal static Command CreateSystemCommand(ICaiCommandRuntime runtime)
    {
        var command = new Command("system", "Container-internal runtime commands.");

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
            runtime.RunSystemInitAsync(
                new SystemInitCommandOptions(
                    DataDir: parseResult.GetValue(dataDirOption),
                    HomeDir: parseResult.GetValue(homeDirOption),
                    ManifestsDir: parseResult.GetValue(manifestsDirOption),
                    TemplateHooks: parseResult.GetValue(templateHooksOption),
                    WorkspaceHooks: parseResult.GetValue(workspaceHooksOption),
                    WorkspaceDir: parseResult.GetValue(workspaceDirOption),
                    Quiet: parseResult.GetValue(quietOption)),
                cancellationToken));

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
            runtime.RunSystemLinkRepairAsync(
                new SystemLinkRepairCommandOptions(
                    Check: parseResult.GetValue(checkOption),
                    Fix: parseResult.GetValue(fixOption),
                    DryRun: parseResult.GetValue(dryRunOption),
                    Quiet: parseResult.GetValue(linkQuietOption),
                    BuiltinSpec: parseResult.GetValue(builtinSpecOption),
                    UserSpec: parseResult.GetValue(userSpecOption),
                    CheckedAtFile: parseResult.GetValue(checkedAtFileOption)),
                cancellationToken));

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
            runtime.RunSystemWatchLinksAsync(
                new SystemWatchLinksCommandOptions(
                    PollInterval: parseResult.GetValue(pollIntervalOption),
                    ImportedAtFile: parseResult.GetValue(importedAtFileOption),
                    CheckedAtFile: parseResult.GetValue(watchCheckedAtFileOption),
                    Quiet: parseResult.GetValue(watchQuietOption)),
                cancellationToken));

        var devcontainer = new Command("devcontainer");

        var install = new Command("install");
        var featureDirOption = new Option<string?>("--feature-dir");
        install.Options.Add(featureDirOption);
        install.SetAction((parseResult, cancellationToken) =>
            runtime.RunSystemDevcontainerInstallAsync(
                new SystemDevcontainerInstallCommandOptions(
                    FeatureDir: parseResult.GetValue(featureDirOption)),
                cancellationToken));

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
}
