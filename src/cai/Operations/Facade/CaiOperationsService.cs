using ContainAI.Cli.Abstractions;
using ContainAI.Cli.Host.RuntimeSupport.Docker;

namespace ContainAI.Cli.Host;

internal sealed class CaiOperationsService
{
    private static readonly string[] ContainAiImagePrefixes =
    [
        "containai:",
        "ghcr.io/containai/",
        "ghcr.io/novotnyllc/containai",
    ];

    private readonly CaiDiagnosticsCommandHandler diagnosticsHandler;
    private readonly CaiMaintenanceCommandHandler maintenanceHandler;
    private readonly CaiSystemCommandHandler systemHandler;
    private readonly CaiTemplateSshGcCommandHandler templateSshGcHandler;

    public CaiOperationsService(TextWriter standardOutput, TextWriter standardError)
        : this(standardOutput, standardError, new ManifestTomlParser())
    {
    }

    internal CaiOperationsService(
        TextWriter standardOutput,
        TextWriter standardError,
        IManifestTomlParser manifestTomlParser)
    {
        ArgumentNullException.ThrowIfNull(standardOutput);
        ArgumentNullException.ThrowIfNull(standardError);
        ArgumentNullException.ThrowIfNull(manifestTomlParser);

        var containerRuntimeCommandService = new ContainerRuntimeCommandService(
            standardOutput,
            standardError,
            manifestTomlParser,
            new ContainerRuntimeOptionParser());

        var containerLinkRepairService = new ContainerLinkRepairService(
            standardOutput,
            standardError,
            CaiRuntimeDockerHelpers.ExecuteDockerCommandAsync);

        var sshCleanupOperations = new CaiSshCleanupOperations(standardOutput, standardError);
        var diagnosticsOperations = new CaiDiagnosticsAndSetupOperations(
            standardOutput,
            standardError,
            sshCleanupOperations.RunSshCleanupAsync);

        var maintenanceOperations = new CaiMaintenanceOperations(
            standardOutput,
            standardError,
            containerLinkRepairService,
            diagnosticsOperations.RunDoctorAsync);

        var templateSshAndGcOperations = new CaiTemplateSshAndGcOperations(
            standardOutput,
            standardError,
            ContainAiImagePrefixes,
            maintenanceOperations.RunExportAsync,
            sshCleanupOperations);

        diagnosticsHandler = new CaiDiagnosticsCommandHandler(diagnosticsOperations);
        maintenanceHandler = new CaiMaintenanceCommandHandler(maintenanceOperations);
        systemHandler = new CaiSystemCommandHandler(containerRuntimeCommandService);
        templateSshGcHandler = new CaiTemplateSshGcCommandHandler(templateSshAndGcOperations);
    }

    public static Task<int> RunDockerAsync(DockerCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return CaiDiagnosticsAndSetupOperations.RunDockerAsync(options.DockerArgs, cancellationToken);
    }

    public Task<int> RunStatusAsync(StatusCommandOptions options, CancellationToken cancellationToken)
        => diagnosticsHandler.RunStatusAsync(options, cancellationToken);

    public Task<int> RunDoctorAsync(DoctorCommandOptions options, CancellationToken cancellationToken)
        => diagnosticsHandler.RunDoctorAsync(options, cancellationToken);

    public Task<int> RunDoctorFixAsync(DoctorFixCommandOptions options, CancellationToken cancellationToken)
        => diagnosticsHandler.RunDoctorFixAsync(options, cancellationToken);

    public Task<int> RunValidateAsync(ValidateCommandOptions options, CancellationToken cancellationToken)
        => diagnosticsHandler.RunValidateAsync(options, cancellationToken);

    public Task<int> RunSetupAsync(SetupCommandOptions options, CancellationToken cancellationToken)
        => diagnosticsHandler.RunSetupAsync(options, cancellationToken);

    public Task<int> RunVersionAsync(CancellationToken cancellationToken)
        => diagnosticsHandler.RunVersionAsync(cancellationToken);

    public Task<int> RunExportAsync(ExportCommandOptions options, CancellationToken cancellationToken)
        => maintenanceHandler.RunExportAsync(options, cancellationToken);

    public Task<int> RunSyncAsync(CancellationToken cancellationToken)
        => maintenanceHandler.RunSyncAsync(cancellationToken);

    public Task<int> RunUpdateAsync(UpdateCommandOptions options, CancellationToken cancellationToken)
        => maintenanceHandler.RunUpdateAsync(options, cancellationToken);

    public Task<int> RunRefreshAsync(RefreshCommandOptions options, CancellationToken cancellationToken)
        => maintenanceHandler.RunRefreshAsync(options, cancellationToken);

    public Task<int> RunUninstallAsync(UninstallCommandOptions options, CancellationToken cancellationToken)
        => maintenanceHandler.RunUninstallAsync(options, cancellationToken);

    public Task<int> RunLinksCheckAsync(LinksSubcommandOptions options, CancellationToken cancellationToken)
        => maintenanceHandler.RunLinksCheckAsync(options, cancellationToken);

    public Task<int> RunLinksFixAsync(LinksSubcommandOptions options, CancellationToken cancellationToken)
        => maintenanceHandler.RunLinksFixAsync(options, cancellationToken);

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

    public Task<int> RunStopAsync(StopCommandOptions options, CancellationToken cancellationToken)
        => templateSshGcHandler.RunStopAsync(options, cancellationToken);

    public Task<int> RunGcAsync(GcCommandOptions options, CancellationToken cancellationToken)
        => templateSshGcHandler.RunGcAsync(options, cancellationToken);

    public Task<int> RunSshCleanupAsync(SshCleanupCommandOptions options, CancellationToken cancellationToken)
        => templateSshGcHandler.RunSshCleanupAsync(options, cancellationToken);

    public Task<int> RunTemplateUpgradeAsync(TemplateUpgradeCommandOptions options, CancellationToken cancellationToken)
        => templateSshGcHandler.RunTemplateUpgradeAsync(options, cancellationToken);
}
