using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed class CaiCommandRuntime : ICaiCommandRuntime
{
    private readonly AcpProxyRunner acpProxyRunner;
    private readonly SessionCommandRuntime sessionRuntime;
    private readonly CaiOperationsService operationsService;
    private readonly CaiConfigManifestService configManifestService;
    private readonly CaiImportService importService;
    private readonly ExamplesCommandRuntime examplesRuntime;
    private readonly InstallCommandRuntime installRuntime;

    // Exposed for tests via reflection-backed console bridge.
    private readonly TextWriter stdout;
    private readonly TextWriter stderr;

    public CaiCommandRuntime(TextWriter? standardOutput = null, TextWriter? standardError = null)
        : this(new AcpProxyRunner(), standardOutput, standardError)
    {
    }

    public CaiCommandRuntime(
        AcpProxyRunner proxyRunner,
        TextWriter? standardOutput = null,
        TextWriter? standardError = null)
        : this(proxyRunner, new ManifestTomlParser(), standardOutput, standardError)
    {
    }

    internal CaiCommandRuntime(
        AcpProxyRunner proxyRunner,
        IManifestTomlParser manifestTomlParser,
        TextWriter? standardOutput = null,
        TextWriter? standardError = null)
    {
        ArgumentNullException.ThrowIfNull(proxyRunner);
        ArgumentNullException.ThrowIfNull(manifestTomlParser);

        acpProxyRunner = proxyRunner;
        stdout = standardOutput ?? Console.Out;
        stderr = standardError ?? Console.Error;

        sessionRuntime = new SessionCommandRuntime(stdout, stderr);
        operationsService = new CaiOperationsService(stdout, stderr, manifestTomlParser);
        configManifestService = new CaiConfigManifestService(stdout, stderr, manifestTomlParser);
        importService = new CaiImportService(stdout, stderr, manifestTomlParser);
        installRuntime = new InstallCommandRuntime();
        examplesRuntime = new ExamplesCommandRuntime();
    }

    public Task<int> RunRunAsync(RunCommandOptions options, CancellationToken cancellationToken)
        => sessionRuntime.RunRunAsync(options, cancellationToken);

    public Task<int> RunShellAsync(ShellCommandOptions options, CancellationToken cancellationToken)
        => sessionRuntime.RunShellAsync(options, cancellationToken);

    public Task<int> RunExecAsync(ExecCommandOptions options, CancellationToken cancellationToken)
        => sessionRuntime.RunExecAsync(options, cancellationToken);

    public Task<int> RunDockerAsync(DockerCommandOptions options, CancellationToken cancellationToken)
        => CaiOperationsService.RunDockerAsync(options, cancellationToken);

    public Task<int> RunStatusAsync(StatusCommandOptions options, CancellationToken cancellationToken)
        => operationsService.RunStatusAsync(options, cancellationToken);

    public Task<int> RunDoctorAsync(DoctorCommandOptions options, CancellationToken cancellationToken)
        => operationsService.RunDoctorAsync(options, cancellationToken);

    public Task<int> RunDoctorFixAsync(DoctorFixCommandOptions options, CancellationToken cancellationToken)
        => operationsService.RunDoctorFixAsync(options, cancellationToken);

    public Task<int> RunValidateAsync(ValidateCommandOptions options, CancellationToken cancellationToken)
        => operationsService.RunValidateAsync(options, cancellationToken);

    public Task<int> RunSetupAsync(SetupCommandOptions options, CancellationToken cancellationToken)
        => operationsService.RunSetupAsync(options, cancellationToken);

    public Task<int> RunImportAsync(ImportCommandOptions options, CancellationToken cancellationToken)
        => importService.RunImportAsync(options, cancellationToken);

    public Task<int> RunExportAsync(ExportCommandOptions options, CancellationToken cancellationToken)
        => operationsService.RunExportAsync(options, cancellationToken);

    public Task<int> RunSyncAsync(CancellationToken cancellationToken)
        => operationsService.RunSyncAsync(cancellationToken);

    public Task<int> RunStopAsync(StopCommandOptions options, CancellationToken cancellationToken)
        => operationsService.RunStopAsync(options, cancellationToken);

    public Task<int> RunGcAsync(GcCommandOptions options, CancellationToken cancellationToken)
        => operationsService.RunGcAsync(options, cancellationToken);

    public Task<int> RunSshCleanupAsync(SshCleanupCommandOptions options, CancellationToken cancellationToken)
        => operationsService.RunSshCleanupAsync(options, cancellationToken);

    public Task<int> RunLinksCheckAsync(LinksSubcommandOptions options, CancellationToken cancellationToken)
        => operationsService.RunLinksCheckAsync(options, cancellationToken);

    public Task<int> RunLinksFixAsync(LinksSubcommandOptions options, CancellationToken cancellationToken)
        => operationsService.RunLinksFixAsync(options, cancellationToken);

    public Task<int> RunConfigListAsync(ConfigListCommandOptions options, CancellationToken cancellationToken)
        => configManifestService.RunConfigListAsync(options, cancellationToken);

    public Task<int> RunConfigGetAsync(ConfigGetCommandOptions options, CancellationToken cancellationToken)
        => configManifestService.RunConfigGetAsync(options, cancellationToken);

    public Task<int> RunConfigSetAsync(ConfigSetCommandOptions options, CancellationToken cancellationToken)
        => configManifestService.RunConfigSetAsync(options, cancellationToken);

    public Task<int> RunConfigUnsetAsync(ConfigUnsetCommandOptions options, CancellationToken cancellationToken)
        => configManifestService.RunConfigUnsetAsync(options, cancellationToken);

    public Task<int> RunConfigResolveVolumeAsync(ConfigResolveVolumeCommandOptions options, CancellationToken cancellationToken)
        => configManifestService.RunConfigResolveVolumeAsync(options, cancellationToken);

    public Task<int> RunManifestParseAsync(ManifestParseCommandOptions options, CancellationToken cancellationToken)
        => configManifestService.RunManifestParseAsync(options, cancellationToken);

    public Task<int> RunManifestGenerateAsync(ManifestGenerateCommandOptions options, CancellationToken cancellationToken)
        => configManifestService.RunManifestGenerateAsync(options, cancellationToken);

    public Task<int> RunManifestApplyAsync(ManifestApplyCommandOptions options, CancellationToken cancellationToken)
        => configManifestService.RunManifestApplyAsync(options, cancellationToken);

    public Task<int> RunManifestCheckAsync(ManifestCheckCommandOptions options, CancellationToken cancellationToken)
        => configManifestService.RunManifestCheckAsync(options, cancellationToken);

    public Task<int> RunTemplateUpgradeAsync(TemplateUpgradeCommandOptions options, CancellationToken cancellationToken)
        => operationsService.RunTemplateUpgradeAsync(options, cancellationToken);

    public Task<int> RunUpdateAsync(UpdateCommandOptions options, CancellationToken cancellationToken)
        => operationsService.RunUpdateAsync(options, cancellationToken);

    public Task<int> RunRefreshAsync(RefreshCommandOptions options, CancellationToken cancellationToken)
        => operationsService.RunRefreshAsync(options, cancellationToken);

    public Task<int> RunUninstallAsync(UninstallCommandOptions options, CancellationToken cancellationToken)
        => operationsService.RunUninstallAsync(options, cancellationToken);

    public Task<int> RunSystemInitAsync(SystemInitCommandOptions options, CancellationToken cancellationToken)
        => operationsService.RunSystemInitAsync(options, cancellationToken);

    public Task<int> RunSystemLinkRepairAsync(SystemLinkRepairCommandOptions options, CancellationToken cancellationToken)
        => operationsService.RunSystemLinkRepairAsync(options, cancellationToken);

    public Task<int> RunSystemWatchLinksAsync(SystemWatchLinksCommandOptions options, CancellationToken cancellationToken)
        => operationsService.RunSystemWatchLinksAsync(options, cancellationToken);

    public Task<int> RunSystemDevcontainerInstallAsync(SystemDevcontainerInstallCommandOptions options, CancellationToken cancellationToken)
        => operationsService.RunSystemDevcontainerInstallAsync(options, cancellationToken);

    public Task<int> RunSystemDevcontainerInitAsync(CancellationToken cancellationToken)
        => operationsService.RunSystemDevcontainerInitAsync(cancellationToken);

    public Task<int> RunSystemDevcontainerStartAsync(CancellationToken cancellationToken)
        => operationsService.RunSystemDevcontainerStartAsync(cancellationToken);

    public Task<int> RunSystemDevcontainerVerifySysboxAsync(CancellationToken cancellationToken)
        => operationsService.RunSystemDevcontainerVerifySysboxAsync(cancellationToken);

    public Task<int> RunVersionAsync(CancellationToken cancellationToken)
        => operationsService.RunVersionAsync(cancellationToken);

    public Task<int> RunAcpProxyAsync(string agent, CancellationToken cancellationToken)
        => acpProxyRunner.RunAsync(agent, cancellationToken);

    public Task<int> RunInstallAsync(InstallCommandOptions options, CancellationToken cancellationToken)
        => installRuntime.RunAsync(options, cancellationToken);

    public Task<int> RunExamplesListAsync(CancellationToken cancellationToken)
        => examplesRuntime.RunListAsync(cancellationToken);

    public Task<int> RunExamplesExportAsync(ExamplesExportCommandOptions options, CancellationToken cancellationToken)
        => examplesRuntime.RunExportAsync(options, cancellationToken);
}
