using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed partial class CaiCommandRuntime
{
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

    public Task<int> RunTemplateUpgradeAsync(TemplateUpgradeCommandOptions options, CancellationToken cancellationToken)
        => operationsService.RunTemplateUpgradeAsync(options, cancellationToken);

    public Task<int> RunUpdateAsync(UpdateCommandOptions options, CancellationToken cancellationToken)
        => operationsService.RunUpdateAsync(options, cancellationToken);

    public Task<int> RunRefreshAsync(RefreshCommandOptions options, CancellationToken cancellationToken)
        => operationsService.RunRefreshAsync(options, cancellationToken);

    public Task<int> RunUninstallAsync(UninstallCommandOptions options, CancellationToken cancellationToken)
        => operationsService.RunUninstallAsync(options, cancellationToken);

    public Task<int> RunVersionAsync(CancellationToken cancellationToken)
        => operationsService.RunVersionAsync(cancellationToken);
}
