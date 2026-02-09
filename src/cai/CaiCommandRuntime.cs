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
        => RunWithOptions(options, nativeLifecycleRuntime.RunRunAsync, cancellationToken);

    public Task<int> RunShellAsync(ShellCommandOptions options, CancellationToken cancellationToken)
        => RunWithOptions(options, nativeLifecycleRuntime.RunShellAsync, cancellationToken);

    public Task<int> RunExecAsync(ExecCommandOptions options, CancellationToken cancellationToken)
        => RunWithOptions(options, nativeLifecycleRuntime.RunExecAsync, cancellationToken);

    public Task<int> RunDockerAsync(DockerCommandOptions options, CancellationToken cancellationToken)
        => RunWithOptions(options, NativeLifecycleCommandRuntime.RunDockerAsync, cancellationToken);

    public Task<int> RunStatusAsync(StatusCommandOptions options, CancellationToken cancellationToken)
        => RunWithOptions(options, nativeLifecycleRuntime.RunStatusAsync, cancellationToken);

    public Task<int> RunDoctorAsync(DoctorCommandOptions options, CancellationToken cancellationToken)
        => RunWithOptions(options, nativeLifecycleRuntime.RunDoctorAsync, cancellationToken);

    public Task<int> RunDoctorFixAsync(DoctorFixCommandOptions options, CancellationToken cancellationToken)
        => RunWithOptions(options, nativeLifecycleRuntime.RunDoctorFixAsync, cancellationToken);

    public Task<int> RunValidateAsync(ValidateCommandOptions options, CancellationToken cancellationToken)
        => RunWithOptions(options, nativeLifecycleRuntime.RunValidateAsync, cancellationToken);

    public Task<int> RunSetupAsync(SetupCommandOptions options, CancellationToken cancellationToken)
        => RunWithOptions(options, nativeLifecycleRuntime.RunSetupAsync, cancellationToken);

    public Task<int> RunImportAsync(ImportCommandOptions options, CancellationToken cancellationToken)
        => RunWithOptions(options, nativeLifecycleRuntime.RunImportAsync, cancellationToken);

    public Task<int> RunExportAsync(ExportCommandOptions options, CancellationToken cancellationToken)
        => RunWithOptions(options, nativeLifecycleRuntime.RunExportAsync, cancellationToken);

    public Task<int> RunSyncAsync(CancellationToken cancellationToken)
        => nativeLifecycleRuntime.RunSyncCommandAsync(cancellationToken);

    public Task<int> RunStopAsync(StopCommandOptions options, CancellationToken cancellationToken)
        => RunWithOptions(options, nativeLifecycleRuntime.RunStopAsync, cancellationToken);

    public Task<int> RunGcAsync(GcCommandOptions options, CancellationToken cancellationToken)
        => RunWithOptions(options, nativeLifecycleRuntime.RunGcAsync, cancellationToken);

    public Task<int> RunSshAsync(CancellationToken cancellationToken)
        => nativeLifecycleRuntime.RunSshCommandAsync(cancellationToken);

    public Task<int> RunSshCleanupAsync(SshCleanupCommandOptions options, CancellationToken cancellationToken)
        => RunWithOptions(options, nativeLifecycleRuntime.RunSshCleanupAsync, cancellationToken);

    public Task<int> RunLinksAsync(CancellationToken cancellationToken)
        => nativeLifecycleRuntime.RunLinksCommandAsync(cancellationToken);

    public Task<int> RunLinksCheckAsync(LinksSubcommandOptions options, CancellationToken cancellationToken)
        => RunWithOptions(options, nativeLifecycleRuntime.RunLinksCheckAsync, cancellationToken);

    public Task<int> RunLinksFixAsync(LinksSubcommandOptions options, CancellationToken cancellationToken)
        => RunWithOptions(options, nativeLifecycleRuntime.RunLinksFixAsync, cancellationToken);

    public Task<int> RunConfigAsync(CancellationToken cancellationToken)
        => nativeLifecycleRuntime.RunConfigCommandAsync(cancellationToken);

    public Task<int> RunConfigListAsync(ConfigListCommandOptions options, CancellationToken cancellationToken)
        => RunWithOptions(options, nativeLifecycleRuntime.RunConfigListAsync, cancellationToken);

    public Task<int> RunConfigGetAsync(ConfigGetCommandOptions options, CancellationToken cancellationToken)
        => RunWithOptions(options, nativeLifecycleRuntime.RunConfigGetAsync, cancellationToken);

    public Task<int> RunConfigSetAsync(ConfigSetCommandOptions options, CancellationToken cancellationToken)
        => RunWithOptions(options, nativeLifecycleRuntime.RunConfigSetAsync, cancellationToken);

    public Task<int> RunConfigUnsetAsync(ConfigUnsetCommandOptions options, CancellationToken cancellationToken)
        => RunWithOptions(options, nativeLifecycleRuntime.RunConfigUnsetAsync, cancellationToken);

    public Task<int> RunConfigResolveVolumeAsync(ConfigResolveVolumeCommandOptions options, CancellationToken cancellationToken)
        => RunWithOptions(options, nativeLifecycleRuntime.RunConfigResolveVolumeAsync, cancellationToken);

    public Task<int> RunManifestAsync(CancellationToken cancellationToken)
        => nativeLifecycleRuntime.RunManifestCommandAsync(cancellationToken);

    public Task<int> RunManifestParseAsync(ManifestParseCommandOptions options, CancellationToken cancellationToken)
        => RunWithOptions(options, nativeLifecycleRuntime.RunManifestParseAsync, cancellationToken);

    public Task<int> RunManifestGenerateAsync(ManifestGenerateCommandOptions options, CancellationToken cancellationToken)
        => RunWithOptions(options, nativeLifecycleRuntime.RunManifestGenerateAsync, cancellationToken);

    public Task<int> RunManifestApplyAsync(ManifestApplyCommandOptions options, CancellationToken cancellationToken)
        => RunWithOptions(options, nativeLifecycleRuntime.RunManifestApplyAsync, cancellationToken);

    public Task<int> RunManifestCheckAsync(ManifestCheckCommandOptions options, CancellationToken cancellationToken)
        => RunWithOptions(options, nativeLifecycleRuntime.RunManifestCheckAsync, cancellationToken);

    public Task<int> RunTemplateAsync(CancellationToken cancellationToken)
        => nativeLifecycleRuntime.RunTemplateCommandAsync(cancellationToken);

    public Task<int> RunTemplateUpgradeAsync(TemplateUpgradeCommandOptions options, CancellationToken cancellationToken)
        => RunWithOptions(options, nativeLifecycleRuntime.RunTemplateUpgradeAsync, cancellationToken);

    public Task<int> RunUpdateAsync(UpdateCommandOptions options, CancellationToken cancellationToken)
        => RunWithOptions(options, nativeLifecycleRuntime.RunUpdateAsync, cancellationToken);

    public Task<int> RunRefreshAsync(RefreshCommandOptions options, CancellationToken cancellationToken)
        => RunWithOptions(options, nativeLifecycleRuntime.RunRefreshAsync, cancellationToken);

    public Task<int> RunUninstallAsync(UninstallCommandOptions options, CancellationToken cancellationToken)
        => RunWithOptions(options, nativeLifecycleRuntime.RunUninstallAsync, cancellationToken);

    public Task<int> RunHelpAsync(HelpCommandOptions options, CancellationToken cancellationToken)
        => RunWithOptions(options, nativeLifecycleRuntime.RunHelpAsync, cancellationToken);

    public Task<int> RunSystemAsync(CancellationToken cancellationToken)
        => nativeLifecycleRuntime.RunSystemCommandAsync(cancellationToken);

    public Task<int> RunSystemInitAsync(SystemInitCommandOptions options, CancellationToken cancellationToken)
        => RunWithOptions(options, nativeLifecycleRuntime.RunSystemInitAsync, cancellationToken);

    public Task<int> RunSystemLinkRepairAsync(SystemLinkRepairCommandOptions options, CancellationToken cancellationToken)
        => RunWithOptions(options, nativeLifecycleRuntime.RunSystemLinkRepairAsync, cancellationToken);

    public Task<int> RunSystemWatchLinksAsync(SystemWatchLinksCommandOptions options, CancellationToken cancellationToken)
        => RunWithOptions(options, nativeLifecycleRuntime.RunSystemWatchLinksAsync, cancellationToken);

    public Task<int> RunSystemDevcontainerAsync(CancellationToken cancellationToken)
        => nativeLifecycleRuntime.RunSystemDevcontainerCommandAsync(cancellationToken);

    public Task<int> RunSystemDevcontainerInstallAsync(SystemDevcontainerInstallCommandOptions options, CancellationToken cancellationToken)
        => RunWithOptions(options, nativeLifecycleRuntime.RunSystemDevcontainerInstallAsync, cancellationToken);

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
        => RunWithOptions(options, installRuntime.RunAsync, cancellationToken);

    public Task<int> RunExamplesListAsync(CancellationToken cancellationToken)
        => examplesRuntime.RunListAsync(cancellationToken);

    public Task<int> RunExamplesExportAsync(ExamplesExportCommandOptions options, CancellationToken cancellationToken)
        => RunWithOptions(options, examplesRuntime.RunExportAsync, cancellationToken);

    private static Task<int> RunWithOptions<TOptions>(
        TOptions options,
        Func<TOptions, CancellationToken, Task<int>> operation,
        CancellationToken cancellationToken)
        where TOptions : class
    {
        ArgumentNullException.ThrowIfNull(options);
        return operation(options, cancellationToken);
    }
}
