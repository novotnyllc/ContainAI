using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Tests;

internal readonly record struct CaiRuntimeExitCodes(
    int Run,
    int Shell,
    int Exec,
    int Docker,
    int Status,
    int Runtime,
    int Acp,
    int Install,
    int ExamplesList,
    int ExamplesExport);

internal abstract class RecordingCaiRuntimeBase : ICaiCommandRuntime
{
    private readonly CaiRuntimeExitCodes exitCodes;

    protected RecordingCaiRuntimeBase(CaiRuntimeExitCodes exitCodes)
        => this.exitCodes = exitCodes;

    public List<RunCommandOptions> RunCalls { get; } = [];

    public List<ShellCommandOptions> ShellCalls { get; } = [];

    public List<ExecCommandOptions> ExecCalls { get; } = [];

    public List<DockerCommandOptions> DockerCalls { get; } = [];

    public List<StatusCommandOptions> StatusCalls { get; } = [];

    public List<IReadOnlyList<string>> RuntimeCalls { get; } = [];

    public List<string> AcpCalls { get; } = [];

    public List<InstallCommandOptions> InstallCalls { get; } = [];

    public int ExamplesListCalls { get; private set; }

    public List<ExamplesExportCommandOptions> ExamplesExportCalls { get; } = [];

    public Task<int> RunRunAsync(RunCommandOptions options, CancellationToken cancellationToken)
    {
        RunCalls.Add(options);
        return Task.FromResult(exitCodes.Run);
    }

    public Task<int> RunShellAsync(ShellCommandOptions options, CancellationToken cancellationToken)
    {
        ShellCalls.Add(options);
        return Task.FromResult(exitCodes.Shell);
    }

    public Task<int> RunExecAsync(ExecCommandOptions options, CancellationToken cancellationToken)
    {
        ExecCalls.Add(options);
        return Task.FromResult(exitCodes.Exec);
    }

    public Task<int> RunDockerAsync(DockerCommandOptions options, CancellationToken cancellationToken)
    {
        DockerCalls.Add(options);
        return Task.FromResult(exitCodes.Docker);
    }

    public Task<int> RunStatusAsync(StatusCommandOptions options, CancellationToken cancellationToken)
    {
        StatusCalls.Add(options);
        return Task.FromResult(exitCodes.Status);
    }

    public Task<int> RunDoctorAsync(DoctorCommandOptions options, CancellationToken cancellationToken)
    {
        var args = new List<string>();
        AppendFlag(args, "--json", options.Json);
        AppendFlag(args, "--build-templates", options.BuildTemplates);
        AppendFlag(args, "--reset-lima", options.ResetLima);
        return RecordRuntimeCall(["doctor"], args);
    }

    public Task<int> RunDoctorFixAsync(DoctorFixCommandOptions options, CancellationToken cancellationToken)
    {
        var args = new List<string>();
        AppendFlag(args, "--all", options.All);
        AppendFlag(args, "--dry-run", options.DryRun);
        AppendArgument(args, options.Target);
        AppendArgument(args, options.TargetArg);
        return RecordRuntimeCall(["doctor", "fix"], args);
    }

    public Task<int> RunValidateAsync(ValidateCommandOptions options, CancellationToken cancellationToken)
    {
        var args = new List<string>();
        AppendFlag(args, "--json", options.Json);
        return RecordRuntimeCall(["validate"], args);
    }

    public Task<int> RunSetupAsync(SetupCommandOptions options, CancellationToken cancellationToken)
    {
        var args = new List<string>();
        AppendFlag(args, "--dry-run", options.DryRun);
        AppendFlag(args, "--verbose", options.Verbose);
        AppendFlag(args, "--skip-templates", options.SkipTemplates);
        return RecordRuntimeCall(["setup"], args);
    }

    public Task<int> RunImportAsync(ImportCommandOptions options, CancellationToken cancellationToken)
    {
        var args = new List<string>();
        AppendOption(args, "--from", options.From);
        AppendOption(args, "--data-volume", options.DataVolume);
        AppendOption(args, "--workspace", options.Workspace);
        AppendOption(args, "--config", options.Config);
        AppendFlag(args, "--dry-run", options.DryRun);
        AppendFlag(args, "--no-excludes", options.NoExcludes);
        AppendFlag(args, "--no-secrets", options.NoSecrets);
        AppendFlag(args, "--verbose", options.Verbose);
        return RecordRuntimeCall(["import"], args);
    }

    public Task<int> RunExportAsync(ExportCommandOptions options, CancellationToken cancellationToken)
    {
        var args = new List<string>();
        AppendOption(args, "--output", options.Output);
        AppendOption(args, "--data-volume", options.DataVolume);
        AppendOption(args, "--container", options.Container);
        AppendOption(args, "--workspace", options.Workspace);
        return RecordRuntimeCall(["export"], args);
    }

    public Task<int> RunSyncAsync(CancellationToken cancellationToken)
        => RecordRuntimeCall(["sync"]);

    public Task<int> RunStopAsync(StopCommandOptions options, CancellationToken cancellationToken)
    {
        var args = new List<string>();
        AppendFlag(args, "--all", options.All);
        AppendOption(args, "--container", options.Container);
        AppendFlag(args, "--remove", options.Remove);
        AppendFlag(args, "--force", options.Force);
        AppendFlag(args, "--export", options.Export);
        AppendFlag(args, "--verbose", options.Verbose);
        return RecordRuntimeCall(["stop"], args);
    }

    public Task<int> RunGcAsync(GcCommandOptions options, CancellationToken cancellationToken)
    {
        var args = new List<string>();
        AppendFlag(args, "--dry-run", options.DryRun);
        AppendFlag(args, "--force", options.Force);
        AppendFlag(args, "--images", options.Images);
        AppendOption(args, "--age", options.Age);
        return RecordRuntimeCall(["gc"], args);
    }

    public Task<int> RunSshCleanupAsync(SshCleanupCommandOptions options, CancellationToken cancellationToken)
    {
        var args = new List<string>();
        AppendFlag(args, "--dry-run", options.DryRun);
        return RecordRuntimeCall(["ssh", "cleanup"], args);
    }

    public Task<int> RunLinksCheckAsync(LinksSubcommandOptions options, CancellationToken cancellationToken)
    {
        var args = new List<string>();
        AppendOption(args, "--name", options.Name);
        AppendOption(args, "--container", options.Container);
        AppendOption(args, "--workspace", options.Workspace);
        AppendFlag(args, "--dry-run", options.DryRun);
        AppendFlag(args, "--quiet", options.Quiet);
        AppendFlag(args, "--verbose", options.Verbose);
        AppendOption(args, "--config", options.Config);
        return RecordRuntimeCall(["links", "check"], args);
    }

    public Task<int> RunLinksFixAsync(LinksSubcommandOptions options, CancellationToken cancellationToken)
    {
        var args = new List<string>();
        AppendOption(args, "--name", options.Name);
        AppendOption(args, "--container", options.Container);
        AppendOption(args, "--workspace", options.Workspace);
        AppendFlag(args, "--dry-run", options.DryRun);
        AppendFlag(args, "--quiet", options.Quiet);
        AppendFlag(args, "--verbose", options.Verbose);
        AppendOption(args, "--config", options.Config);
        return RecordRuntimeCall(["links", "fix"], args);
    }

    public Task<int> RunConfigListAsync(ConfigListCommandOptions options, CancellationToken cancellationToken)
    {
        var args = new List<string>();
        AppendFlag(args, "--global", options.Global);
        AppendOption(args, "--workspace", options.Workspace);
        AppendFlag(args, "--verbose", options.Verbose);
        args.Add("list");
        return RecordRuntimeCall(["config"], args);
    }

    public Task<int> RunConfigGetAsync(ConfigGetCommandOptions options, CancellationToken cancellationToken)
    {
        var args = new List<string>();
        AppendFlag(args, "--global", options.Global);
        AppendOption(args, "--workspace", options.Workspace);
        AppendFlag(args, "--verbose", options.Verbose);
        args.Add("get");
        args.Add(options.Key);
        return RecordRuntimeCall(["config"], args);
    }

    public Task<int> RunConfigSetAsync(ConfigSetCommandOptions options, CancellationToken cancellationToken)
    {
        var args = new List<string>();
        AppendFlag(args, "--global", options.Global);
        AppendOption(args, "--workspace", options.Workspace);
        AppendFlag(args, "--verbose", options.Verbose);
        args.Add("set");
        args.Add(options.Key);
        args.Add(options.Value);
        return RecordRuntimeCall(["config"], args);
    }

    public Task<int> RunConfigUnsetAsync(ConfigUnsetCommandOptions options, CancellationToken cancellationToken)
    {
        var args = new List<string>();
        AppendFlag(args, "--global", options.Global);
        AppendOption(args, "--workspace", options.Workspace);
        AppendFlag(args, "--verbose", options.Verbose);
        args.Add("unset");
        args.Add(options.Key);
        return RecordRuntimeCall(["config"], args);
    }

    public Task<int> RunConfigResolveVolumeAsync(ConfigResolveVolumeCommandOptions options, CancellationToken cancellationToken)
    {
        var args = new List<string>();
        AppendFlag(args, "--global", options.Global);
        AppendOption(args, "--workspace", options.Workspace);
        AppendFlag(args, "--verbose", options.Verbose);
        args.Add("resolve-volume");
        AppendArgument(args, options.ExplicitVolume);
        return RecordRuntimeCall(["config"], args);
    }

    public Task<int> RunManifestParseAsync(ManifestParseCommandOptions options, CancellationToken cancellationToken)
    {
        var args = new List<string>();
        AppendFlag(args, "--include-disabled", options.IncludeDisabled);
        AppendFlag(args, "--emit-source-file", options.EmitSourceFile);
        args.Add(options.ManifestPath);
        return RecordRuntimeCall(["manifest", "parse"], args);
    }

    public Task<int> RunManifestGenerateAsync(ManifestGenerateCommandOptions options, CancellationToken cancellationToken)
    {
        var args = new List<string> { options.Kind, options.ManifestPath };
        AppendArgument(args, options.OutputPath);
        return RecordRuntimeCall(["manifest", "generate"], args);
    }

    public Task<int> RunManifestApplyAsync(ManifestApplyCommandOptions options, CancellationToken cancellationToken)
    {
        var args = new List<string> { options.Kind, options.ManifestPath };
        AppendOption(args, "--data-dir", options.DataDir);
        AppendOption(args, "--home-dir", options.HomeDir);
        AppendOption(args, "--shim-dir", options.ShimDir);
        AppendOption(args, "--cai-binary", options.CaiBinary);
        return RecordRuntimeCall(["manifest", "apply"], args);
    }

    public Task<int> RunManifestCheckAsync(ManifestCheckCommandOptions options, CancellationToken cancellationToken)
    {
        var args = new List<string>();
        AppendOption(args, "--manifest-dir", options.ManifestDir);
        return RecordRuntimeCall(["manifest", "check"], args);
    }

    public Task<int> RunTemplateUpgradeAsync(TemplateUpgradeCommandOptions options, CancellationToken cancellationToken)
    {
        var args = new List<string>();
        AppendArgument(args, options.Name);
        AppendFlag(args, "--dry-run", options.DryRun);
        return RecordRuntimeCall(["template", "upgrade"], args);
    }

    public Task<int> RunUpdateAsync(UpdateCommandOptions options, CancellationToken cancellationToken)
    {
        var args = new List<string>();
        AppendFlag(args, "--dry-run", options.DryRun);
        AppendFlag(args, "--stop-containers", options.StopContainers);
        AppendFlag(args, "--force", options.Force);
        AppendFlag(args, "--lima-recreate", options.LimaRecreate);
        AppendFlag(args, "--verbose", options.Verbose);
        return RecordRuntimeCall(["update"], args);
    }

    public Task<int> RunRefreshAsync(RefreshCommandOptions options, CancellationToken cancellationToken)
    {
        var args = new List<string>();
        AppendFlag(args, "--rebuild", options.Rebuild);
        AppendFlag(args, "--verbose", options.Verbose);
        return RecordRuntimeCall(["refresh"], args);
    }

    public Task<int> RunUninstallAsync(UninstallCommandOptions options, CancellationToken cancellationToken)
    {
        var args = new List<string>();
        AppendFlag(args, "--dry-run", options.DryRun);
        AppendFlag(args, "--containers", options.Containers);
        AppendFlag(args, "--volumes", options.Volumes);
        AppendFlag(args, "--force", options.Force);
        AppendFlag(args, "--verbose", options.Verbose);
        return RecordRuntimeCall(["uninstall"], args);
    }

    public Task<int> RunSystemInitAsync(SystemInitCommandOptions options, CancellationToken cancellationToken)
    {
        var args = new List<string>();
        AppendOption(args, "--data-dir", options.DataDir);
        AppendOption(args, "--home-dir", options.HomeDir);
        AppendOption(args, "--manifests-dir", options.ManifestsDir);
        AppendOption(args, "--template-hooks", options.TemplateHooks);
        AppendOption(args, "--workspace-hooks", options.WorkspaceHooks);
        AppendOption(args, "--workspace-dir", options.WorkspaceDir);
        AppendFlag(args, "--quiet", options.Quiet);
        return RecordRuntimeCall(["system", "init"], args);
    }

    public Task<int> RunSystemLinkRepairAsync(SystemLinkRepairCommandOptions options, CancellationToken cancellationToken)
    {
        var args = new List<string>();
        AppendFlag(args, "--check", options.Check);
        AppendFlag(args, "--fix", options.Fix);
        AppendFlag(args, "--dry-run", options.DryRun);
        AppendFlag(args, "--quiet", options.Quiet);
        AppendOption(args, "--builtin-spec", options.BuiltinSpec);
        AppendOption(args, "--user-spec", options.UserSpec);
        AppendOption(args, "--checked-at-file", options.CheckedAtFile);
        return RecordRuntimeCall(["system", "link-repair"], args);
    }

    public Task<int> RunSystemWatchLinksAsync(SystemWatchLinksCommandOptions options, CancellationToken cancellationToken)
    {
        var args = new List<string>();
        AppendOption(args, "--poll-interval", options.PollInterval);
        AppendOption(args, "--imported-at-file", options.ImportedAtFile);
        AppendOption(args, "--checked-at-file", options.CheckedAtFile);
        AppendFlag(args, "--quiet", options.Quiet);
        return RecordRuntimeCall(["system", "watch-links"], args);
    }

    public Task<int> RunSystemDevcontainerInstallAsync(SystemDevcontainerInstallCommandOptions options, CancellationToken cancellationToken)
    {
        var args = new List<string>();
        AppendOption(args, "--feature-dir", options.FeatureDir);
        return RecordRuntimeCall(["system", "devcontainer", "install"], args);
    }

    public Task<int> RunSystemDevcontainerInitAsync(CancellationToken cancellationToken)
        => RecordRuntimeCall(["system", "devcontainer", "init"]);

    public Task<int> RunSystemDevcontainerStartAsync(CancellationToken cancellationToken)
        => RecordRuntimeCall(["system", "devcontainer", "start"]);

    public Task<int> RunSystemDevcontainerVerifySysboxAsync(CancellationToken cancellationToken)
        => RecordRuntimeCall(["system", "devcontainer", "verify-sysbox"]);

    public Task<int> RunVersionAsync(CancellationToken cancellationToken)
        => RecordRuntimeCall(["version"]);

    public Task<int> RunAcpProxyAsync(string agent, CancellationToken cancellationToken)
    {
        AcpCalls.Add(agent);
        return Task.FromResult(exitCodes.Acp);
    }

    public Task<int> RunInstallAsync(InstallCommandOptions options, CancellationToken cancellationToken)
    {
        InstallCalls.Add(options);
        return Task.FromResult(exitCodes.Install);
    }

    public Task<int> RunExamplesListAsync(CancellationToken cancellationToken)
    {
        ExamplesListCalls++;
        return Task.FromResult(exitCodes.ExamplesList);
    }

    public Task<int> RunExamplesExportAsync(ExamplesExportCommandOptions options, CancellationToken cancellationToken)
    {
        ExamplesExportCalls.Add(options);
        return Task.FromResult(exitCodes.ExamplesExport);
    }

    private Task<int> RecordRuntimeCall(IReadOnlyList<string> args)
    {
        RuntimeCalls.Add(args.ToArray());
        return Task.FromResult(exitCodes.Runtime);
    }

    private Task<int> RecordRuntimeCall(IReadOnlyList<string> commandPath, List<string> args)
        => args.Count == 0
            ? RecordRuntimeCall(commandPath)
            : RecordRuntimeCall([.. commandPath, .. args]);

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
