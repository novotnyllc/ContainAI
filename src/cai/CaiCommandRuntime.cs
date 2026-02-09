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
        => nativeLifecycleRuntime.RunDoctorCommandAsync(args, cancellationToken);

    public Task<int> RunDoctorFixAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => nativeLifecycleRuntime.RunDoctorFixCommandAsync(args, cancellationToken);

    public Task<int> RunValidateAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => nativeLifecycleRuntime.RunValidateCommandAsync(args, cancellationToken);

    public Task<int> RunSetupAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => nativeLifecycleRuntime.RunSetupCommandAsync(args, cancellationToken);

    public Task<int> RunImportAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => nativeLifecycleRuntime.RunImportCommandAsync(args, cancellationToken);

    public Task<int> RunExportAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => nativeLifecycleRuntime.RunExportCommandAsync(args, cancellationToken);

    public Task<int> RunSyncAsync(CancellationToken cancellationToken)
        => nativeLifecycleRuntime.RunSyncCommandAsync(cancellationToken);

    public Task<int> RunStopAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => nativeLifecycleRuntime.RunStopCommandAsync(args, cancellationToken);

    public Task<int> RunGcAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => nativeLifecycleRuntime.RunGcCommandAsync(args, cancellationToken);

    public Task<int> RunSshAsync(CancellationToken cancellationToken)
        => nativeLifecycleRuntime.RunSshCommandAsync(cancellationToken);

    public Task<int> RunSshCleanupAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => nativeLifecycleRuntime.RunSshCleanupCommandAsync(args, cancellationToken);

    public Task<int> RunLinksAsync(CancellationToken cancellationToken)
        => nativeLifecycleRuntime.RunLinksCommandAsync(cancellationToken);

    public Task<int> RunLinksCheckAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => nativeLifecycleRuntime.RunLinksCheckCommandAsync(args, cancellationToken);

    public Task<int> RunLinksFixAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => nativeLifecycleRuntime.RunLinksFixCommandAsync(args, cancellationToken);

    public Task<int> RunConfigAsync(CancellationToken cancellationToken)
        => nativeLifecycleRuntime.RunConfigCommandAsync(cancellationToken);

    public Task<int> RunConfigListAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => nativeLifecycleRuntime.RunConfigListCommandAsync(args, cancellationToken);

    public Task<int> RunConfigGetAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => nativeLifecycleRuntime.RunConfigGetCommandAsync(args, cancellationToken);

    public Task<int> RunConfigSetAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => nativeLifecycleRuntime.RunConfigSetCommandAsync(args, cancellationToken);

    public Task<int> RunConfigUnsetAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => nativeLifecycleRuntime.RunConfigUnsetCommandAsync(args, cancellationToken);

    public Task<int> RunConfigResolveVolumeAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => nativeLifecycleRuntime.RunConfigResolveVolumeCommandAsync(args, cancellationToken);

    public Task<int> RunManifestAsync(CancellationToken cancellationToken)
        => nativeLifecycleRuntime.RunManifestCommandAsync(cancellationToken);

    public Task<int> RunManifestParseAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => nativeLifecycleRuntime.RunManifestParseCommandAsync(args, cancellationToken);

    public Task<int> RunManifestGenerateAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => nativeLifecycleRuntime.RunManifestGenerateCommandAsync(args, cancellationToken);

    public Task<int> RunManifestApplyAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => nativeLifecycleRuntime.RunManifestApplyCommandAsync(args, cancellationToken);

    public Task<int> RunManifestCheckAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => nativeLifecycleRuntime.RunManifestCheckCommandAsync(args, cancellationToken);

    public Task<int> RunTemplateAsync(CancellationToken cancellationToken)
        => nativeLifecycleRuntime.RunTemplateCommandAsync(cancellationToken);

    public Task<int> RunTemplateUpgradeAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => nativeLifecycleRuntime.RunTemplateUpgradeCommandAsync(args, cancellationToken);

    public Task<int> RunUpdateAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => nativeLifecycleRuntime.RunUpdateCommandAsync(args, cancellationToken);

    public Task<int> RunRefreshAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => nativeLifecycleRuntime.RunRefreshCommandAsync(args, cancellationToken);

    public Task<int> RunUninstallAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => nativeLifecycleRuntime.RunUninstallCommandAsync(args, cancellationToken);

    public Task<int> RunHelpAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => nativeLifecycleRuntime.RunHelpCommandAsync(args, cancellationToken);

    public Task<int> RunSystemAsync(CancellationToken cancellationToken)
        => nativeLifecycleRuntime.RunSystemCommandAsync(cancellationToken);

    public Task<int> RunSystemInitAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => nativeLifecycleRuntime.RunSystemInitCommandAsync(args, cancellationToken);

    public Task<int> RunSystemLinkRepairAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => nativeLifecycleRuntime.RunSystemLinkRepairCommandAsync(args, cancellationToken);

    public Task<int> RunSystemWatchLinksAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => nativeLifecycleRuntime.RunSystemWatchLinksCommandAsync(args, cancellationToken);

    public Task<int> RunSystemDevcontainerAsync(CancellationToken cancellationToken)
        => nativeLifecycleRuntime.RunSystemDevcontainerCommandAsync(cancellationToken);

    public Task<int> RunSystemDevcontainerInstallAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => nativeLifecycleRuntime.RunSystemDevcontainerInstallCommandAsync(args, cancellationToken);

    public Task<int> RunSystemDevcontainerInitAsync(CancellationToken cancellationToken)
        => nativeLifecycleRuntime.RunSystemDevcontainerInitCommandAsync(cancellationToken);

    public Task<int> RunSystemDevcontainerStartAsync(CancellationToken cancellationToken)
        => nativeLifecycleRuntime.RunSystemDevcontainerStartCommandAsync(cancellationToken);

    public Task<int> RunSystemDevcontainerVerifySysboxAsync(CancellationToken cancellationToken)
        => nativeLifecycleRuntime.RunSystemDevcontainerVerifySysboxCommandAsync(cancellationToken);

    public Task<int> RunVersionAsync(CancellationToken cancellationToken)
        => nativeLifecycleRuntime.RunVersionCommandAsync(cancellationToken);

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

}
