using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed class CaiCommandRuntime : ICaiCommandRuntime
{
    private readonly CaiRuntimeOperationsCommandHandler operationsHandler;
    private readonly CaiRuntimeConfigCommandHandler configHandler;
    private readonly CaiRuntimeImportCommandHandler importHandler;
    private readonly CaiRuntimeSessionCommandHandler sessionHandler;
    private readonly CaiRuntimeSystemCommandHandler systemHandler;
    private readonly CaiRuntimeToolsCommandHandler toolsHandler;

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

        stdout = standardOutput ?? Console.Out;
        stderr = standardError ?? Console.Error;

        var sessionRuntime = new SessionCommandRuntime(stdout, stderr);
        var operationsService = new CaiOperationsService(stdout, stderr, manifestTomlParser);
        var configManifestService = new CaiConfigManifestService(stdout, stderr, manifestTomlParser);
        var importService = new CaiImportService(stdout, stderr, manifestTomlParser);
        var installRuntime = new InstallCommandRuntime();
        var examplesRuntime = new ExamplesCommandRuntime();

        operationsHandler = new CaiRuntimeOperationsCommandHandler(operationsService);
        configHandler = new CaiRuntimeConfigCommandHandler(configManifestService);
        importHandler = new CaiRuntimeImportCommandHandler(importService);
        sessionHandler = new CaiRuntimeSessionCommandHandler(sessionRuntime);
        systemHandler = new CaiRuntimeSystemCommandHandler(operationsService);
        toolsHandler = new CaiRuntimeToolsCommandHandler(proxyRunner, installRuntime, examplesRuntime);
    }

    public Task<int> RunDockerAsync(DockerCommandOptions options, CancellationToken cancellationToken)
        => operationsHandler.RunDockerAsync(options, cancellationToken);

    public Task<int> RunStatusAsync(StatusCommandOptions options, CancellationToken cancellationToken)
        => operationsHandler.RunStatusAsync(options, cancellationToken);

    public Task<int> RunDoctorAsync(DoctorCommandOptions options, CancellationToken cancellationToken)
        => operationsHandler.RunDoctorAsync(options, cancellationToken);

    public Task<int> RunDoctorFixAsync(DoctorFixCommandOptions options, CancellationToken cancellationToken)
        => operationsHandler.RunDoctorFixAsync(options, cancellationToken);

    public Task<int> RunValidateAsync(ValidateCommandOptions options, CancellationToken cancellationToken)
        => operationsHandler.RunValidateAsync(options, cancellationToken);

    public Task<int> RunSetupAsync(SetupCommandOptions options, CancellationToken cancellationToken)
        => operationsHandler.RunSetupAsync(options, cancellationToken);

    public Task<int> RunImportAsync(ImportCommandOptions options, CancellationToken cancellationToken)
        => importHandler.RunImportAsync(options, cancellationToken);

    public Task<int> RunExportAsync(ExportCommandOptions options, CancellationToken cancellationToken)
        => operationsHandler.RunExportAsync(options, cancellationToken);

    public Task<int> RunSyncAsync(CancellationToken cancellationToken)
        => operationsHandler.RunSyncAsync(cancellationToken);

    public Task<int> RunStopAsync(StopCommandOptions options, CancellationToken cancellationToken)
        => operationsHandler.RunStopAsync(options, cancellationToken);

    public Task<int> RunGcAsync(GcCommandOptions options, CancellationToken cancellationToken)
        => operationsHandler.RunGcAsync(options, cancellationToken);

    public Task<int> RunSshCleanupAsync(SshCleanupCommandOptions options, CancellationToken cancellationToken)
        => operationsHandler.RunSshCleanupAsync(options, cancellationToken);

    public Task<int> RunLinksCheckAsync(LinksSubcommandOptions options, CancellationToken cancellationToken)
        => operationsHandler.RunLinksCheckAsync(options, cancellationToken);

    public Task<int> RunLinksFixAsync(LinksSubcommandOptions options, CancellationToken cancellationToken)
        => operationsHandler.RunLinksFixAsync(options, cancellationToken);

    public Task<int> RunTemplateUpgradeAsync(TemplateUpgradeCommandOptions options, CancellationToken cancellationToken)
        => operationsHandler.RunTemplateUpgradeAsync(options, cancellationToken);

    public Task<int> RunUpdateAsync(UpdateCommandOptions options, CancellationToken cancellationToken)
        => operationsHandler.RunUpdateAsync(options, cancellationToken);

    public Task<int> RunRefreshAsync(RefreshCommandOptions options, CancellationToken cancellationToken)
        => operationsHandler.RunRefreshAsync(options, cancellationToken);

    public Task<int> RunUninstallAsync(UninstallCommandOptions options, CancellationToken cancellationToken)
        => operationsHandler.RunUninstallAsync(options, cancellationToken);

    public Task<int> RunVersionAsync(CancellationToken cancellationToken)
        => operationsHandler.RunVersionAsync(cancellationToken);

    public Task<int> RunRunAsync(RunCommandOptions options, CancellationToken cancellationToken)
        => sessionHandler.RunRunAsync(options, cancellationToken);

    public Task<int> RunShellAsync(ShellCommandOptions options, CancellationToken cancellationToken)
        => sessionHandler.RunShellAsync(options, cancellationToken);

    public Task<int> RunExecAsync(ExecCommandOptions options, CancellationToken cancellationToken)
        => sessionHandler.RunExecAsync(options, cancellationToken);

    public Task<int> RunSystemInitAsync(SystemInitCommandOptions options, CancellationToken cancellationToken)
        => systemHandler.RunSystemInitAsync(options, cancellationToken);

    public Task<int> RunSystemLinkRepairAsync(SystemLinkRepairCommandOptions options, CancellationToken cancellationToken)
        => systemHandler.RunSystemLinkRepairAsync(options, cancellationToken);

    public Task<int> RunSystemWatchLinksAsync(SystemWatchLinksCommandOptions options, CancellationToken cancellationToken)
        => systemHandler.RunSystemWatchLinksAsync(options, cancellationToken);

    public Task<int> RunSystemDevcontainerInstallAsync(SystemDevcontainerInstallCommandOptions options, CancellationToken cancellationToken)
        => systemHandler.RunSystemDevcontainerInstallAsync(options, cancellationToken);

    public Task<int> RunSystemDevcontainerInitAsync(CancellationToken cancellationToken)
        => systemHandler.RunSystemDevcontainerInitAsync(cancellationToken);

    public Task<int> RunSystemDevcontainerStartAsync(CancellationToken cancellationToken)
        => systemHandler.RunSystemDevcontainerStartAsync(cancellationToken);

    public Task<int> RunSystemDevcontainerVerifySysboxAsync(CancellationToken cancellationToken)
        => systemHandler.RunSystemDevcontainerVerifySysboxAsync(cancellationToken);

    public Task<int> RunAcpProxyAsync(string agent, CancellationToken cancellationToken)
        => toolsHandler.RunAcpProxyAsync(agent, cancellationToken);

    public Task<int> RunInstallAsync(InstallCommandOptions options, CancellationToken cancellationToken)
        => toolsHandler.RunInstallAsync(options, cancellationToken);

    public Task<int> RunExamplesListAsync(CancellationToken cancellationToken)
        => toolsHandler.RunExamplesListAsync(cancellationToken);

    public Task<int> RunExamplesExportAsync(ExamplesExportCommandOptions options, CancellationToken cancellationToken)
        => toolsHandler.RunExamplesExportAsync(options, cancellationToken);

    public Task<int> RunConfigListAsync(ConfigListCommandOptions options, CancellationToken cancellationToken)
        => configHandler.RunConfigListAsync(options, cancellationToken);

    public Task<int> RunConfigGetAsync(ConfigGetCommandOptions options, CancellationToken cancellationToken)
        => configHandler.RunConfigGetAsync(options, cancellationToken);

    public Task<int> RunConfigSetAsync(ConfigSetCommandOptions options, CancellationToken cancellationToken)
        => configHandler.RunConfigSetAsync(options, cancellationToken);

    public Task<int> RunConfigUnsetAsync(ConfigUnsetCommandOptions options, CancellationToken cancellationToken)
        => configHandler.RunConfigUnsetAsync(options, cancellationToken);

    public Task<int> RunConfigResolveVolumeAsync(ConfigResolveVolumeCommandOptions options, CancellationToken cancellationToken)
        => configHandler.RunConfigResolveVolumeAsync(options, cancellationToken);

    public Task<int> RunManifestParseAsync(ManifestParseCommandOptions options, CancellationToken cancellationToken)
        => configHandler.RunManifestParseAsync(options, cancellationToken);

    public Task<int> RunManifestGenerateAsync(ManifestGenerateCommandOptions options, CancellationToken cancellationToken)
        => configHandler.RunManifestGenerateAsync(options, cancellationToken);

    public Task<int> RunManifestApplyAsync(ManifestApplyCommandOptions options, CancellationToken cancellationToken)
        => configHandler.RunManifestApplyAsync(options, cancellationToken);

    public Task<int> RunManifestCheckAsync(ManifestCheckCommandOptions options, CancellationToken cancellationToken)
        => configHandler.RunManifestCheckAsync(options, cancellationToken);
}
