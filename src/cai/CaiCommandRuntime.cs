using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed class CaiCommandRuntime : ICaiCommandRuntime
{
    private readonly AcpProxyRunner acpProxyRunner;
    private readonly ExamplesCommandRuntime examplesRuntime;
    private readonly InstallCommandRuntime installRuntime;
    private readonly NativeLifecycleCommandRuntime nativeLifecycleRuntime;

    public CaiCommandRuntime(
        AcpProxyRunner proxyRunner,
        NativeLifecycleCommandRuntime? lifecycleRuntime = null)
    {
        acpProxyRunner = proxyRunner;
        nativeLifecycleRuntime = lifecycleRuntime ?? new NativeLifecycleCommandRuntime();
        installRuntime = new InstallCommandRuntime();
        examplesRuntime = new ExamplesCommandRuntime();
    }

    public Task<int> RunRunAsync(RunCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return nativeLifecycleRuntime.RunRunAsync(options, cancellationToken);
    }

    public Task<int> RunShellAsync(ShellCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return nativeLifecycleRuntime.RunShellAsync(options, cancellationToken);
    }

    public Task<int> RunExecAsync(ExecCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return nativeLifecycleRuntime.RunExecAsync(options, cancellationToken);
    }

    public Task<int> RunDockerAsync(DockerCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return NativeLifecycleCommandRuntime.RunDockerAsync(options, cancellationToken);
    }

    public Task<int> RunStatusAsync(StatusCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return nativeLifecycleRuntime.RunStatusAsync(options, cancellationToken);
    }

    public Task<int> RunDoctorAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => RunNativeCommandAsync(["doctor"], args, cancellationToken);

    public Task<int> RunDoctorFixAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => RunNativeCommandAsync(["doctor", "fix"], args, cancellationToken);

    public Task<int> RunValidateAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => RunNativeCommandAsync(["validate"], args, cancellationToken);

    public Task<int> RunSetupAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => RunNativeCommandAsync(["setup"], args, cancellationToken);

    public Task<int> RunImportAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => RunNativeCommandAsync(["import"], args, cancellationToken);

    public Task<int> RunExportAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => RunNativeCommandAsync(["export"], args, cancellationToken);

    public Task<int> RunSyncAsync(CancellationToken cancellationToken)
        => RunNativeCommandAsync(["sync"], cancellationToken);

    public Task<int> RunStopAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => RunNativeCommandAsync(["stop"], args, cancellationToken);

    public Task<int> RunGcAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => RunNativeCommandAsync(["gc"], args, cancellationToken);

    public Task<int> RunSshAsync(CancellationToken cancellationToken)
        => RunNativeCommandAsync(["ssh"], cancellationToken);

    public Task<int> RunSshCleanupAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => RunNativeCommandAsync(["ssh", "cleanup"], args, cancellationToken);

    public Task<int> RunLinksAsync(CancellationToken cancellationToken)
        => RunNativeCommandAsync(["links"], cancellationToken);

    public Task<int> RunLinksCheckAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => RunNativeCommandAsync(["links", "check"], args, cancellationToken);

    public Task<int> RunLinksFixAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => RunNativeCommandAsync(["links", "fix"], args, cancellationToken);

    public Task<int> RunConfigAsync(CancellationToken cancellationToken)
        => RunNativeCommandAsync(["config"], cancellationToken);

    public Task<int> RunConfigListAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => RunNativeCommandAsync(["config"], args, cancellationToken);

    public Task<int> RunConfigGetAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => RunNativeCommandAsync(["config"], args, cancellationToken);

    public Task<int> RunConfigSetAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => RunNativeCommandAsync(["config"], args, cancellationToken);

    public Task<int> RunConfigUnsetAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => RunNativeCommandAsync(["config"], args, cancellationToken);

    public Task<int> RunConfigResolveVolumeAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => RunNativeCommandAsync(["config"], args, cancellationToken);

    public Task<int> RunManifestAsync(CancellationToken cancellationToken)
        => RunNativeCommandAsync(["manifest"], cancellationToken);

    public Task<int> RunManifestParseAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => RunNativeCommandAsync(["manifest", "parse"], args, cancellationToken);

    public Task<int> RunManifestGenerateAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => RunNativeCommandAsync(["manifest", "generate"], args, cancellationToken);

    public Task<int> RunManifestApplyAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => RunNativeCommandAsync(["manifest", "apply"], args, cancellationToken);

    public Task<int> RunManifestCheckAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => RunNativeCommandAsync(["manifest", "check"], args, cancellationToken);

    public Task<int> RunTemplateAsync(CancellationToken cancellationToken)
        => RunNativeCommandAsync(["template"], cancellationToken);

    public Task<int> RunTemplateUpgradeAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => RunNativeCommandAsync(["template", "upgrade"], args, cancellationToken);

    public Task<int> RunUpdateAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => RunNativeCommandAsync(["update"], args, cancellationToken);

    public Task<int> RunRefreshAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => RunNativeCommandAsync(["refresh"], args, cancellationToken);

    public Task<int> RunUninstallAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => RunNativeCommandAsync(["uninstall"], args, cancellationToken);

    public Task<int> RunHelpAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => RunNativeCommandAsync(["help"], args, cancellationToken);

    public Task<int> RunSystemAsync(CancellationToken cancellationToken)
        => RunNativeCommandAsync(["system"], cancellationToken);

    public Task<int> RunSystemInitAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => RunNativeCommandAsync(["system", "init"], args, cancellationToken);

    public Task<int> RunSystemLinkRepairAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => RunNativeCommandAsync(["system", "link-repair"], args, cancellationToken);

    public Task<int> RunSystemWatchLinksAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => RunNativeCommandAsync(["system", "watch-links"], args, cancellationToken);

    public Task<int> RunSystemDevcontainerAsync(CancellationToken cancellationToken)
        => RunNativeCommandAsync(["system", "devcontainer"], cancellationToken);

    public Task<int> RunSystemDevcontainerInstallAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => RunNativeCommandAsync(["system", "devcontainer", "install"], args, cancellationToken);

    public Task<int> RunSystemDevcontainerInitAsync(CancellationToken cancellationToken)
        => RunNativeCommandAsync(["system", "devcontainer", "init"], cancellationToken);

    public Task<int> RunSystemDevcontainerStartAsync(CancellationToken cancellationToken)
        => RunNativeCommandAsync(["system", "devcontainer", "start"], cancellationToken);

    public Task<int> RunSystemDevcontainerVerifySysboxAsync(CancellationToken cancellationToken)
        => RunNativeCommandAsync(["system", "devcontainer", "verify-sysbox"], cancellationToken);

    public Task<int> RunVersionAsync(CancellationToken cancellationToken)
        => RunNativeCommandAsync(["version"], cancellationToken);

    public Task<int> RunAcpProxyAsync(string agent, CancellationToken cancellationToken)
        => acpProxyRunner.RunAsync(agent, cancellationToken);

    public Task<int> RunInstallAsync(InstallCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return installRuntime.RunAsync(options, cancellationToken);
    }

    public Task<int> RunExamplesListAsync(CancellationToken cancellationToken)
        => examplesRuntime.RunListAsync(cancellationToken);

    public Task<int> RunExamplesExportAsync(ExamplesExportCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return examplesRuntime.RunExportAsync(options, cancellationToken);
    }

    private Task<int> RunNativeCommandAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => nativeLifecycleRuntime.RunAsync(args, cancellationToken);

    private Task<int> RunNativeCommandAsync(IReadOnlyList<string> commandPath, IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(commandPath);
        ArgumentNullException.ThrowIfNull(args);

        return args.Count == 0
            ? RunNativeCommandAsync(commandPath, cancellationToken)
            : RunNativeCommandAsync([.. commandPath, .. args], cancellationToken);
    }

}
