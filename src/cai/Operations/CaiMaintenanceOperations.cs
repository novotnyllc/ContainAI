using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed class CaiMaintenanceOperations : CaiRuntimeSupport
{
    private readonly CaiExportOperations exportOperations;
    private readonly CaiSyncOperations syncOperations;
    private readonly CaiLinksOperations linksOperations;
    private readonly CaiUpdateRefreshOperations updateRefreshOperations;
    private readonly CaiUninstallOperations uninstallOperations;

    public CaiMaintenanceOperations(
        TextWriter standardOutput,
        TextWriter standardError,
        ContainerLinkRepairService containerLinkRepairService,
        Func<bool, bool, bool, CancellationToken, Task<int>> runDoctorAsync)
        : base(standardOutput, standardError)
    {
        exportOperations = new CaiExportOperations(standardOutput, standardError);
        syncOperations = new CaiSyncOperations(standardOutput, standardError);
        linksOperations = new CaiLinksOperations(standardOutput, standardError, containerLinkRepairService);
        updateRefreshOperations = new CaiUpdateRefreshOperations(standardOutput, standardError, runDoctorAsync);
        uninstallOperations = new CaiUninstallOperations(standardOutput, standardError);
    }

    public Task<int> RunExportAsync(
        string? output,
        string? explicitVolume,
        string? container,
        string? workspace,
        CancellationToken cancellationToken)
        => exportOperations.RunExportAsync(output, explicitVolume, container, workspace, cancellationToken);

    public Task<int> RunSyncAsync(CancellationToken cancellationToken)
        => syncOperations.RunSyncAsync(cancellationToken);

    public Task<int> RunLinksAsync(
        string subcommand,
        string? containerName,
        string? workspace,
        bool dryRun,
        bool quiet,
        CancellationToken cancellationToken)
        => linksOperations.RunLinksAsync(subcommand, containerName, workspace, dryRun, quiet, cancellationToken);

    public Task<int> RunUpdateAsync(
        bool dryRun,
        bool stopContainers,
        bool limaRecreate,
        bool showHelp,
        CancellationToken cancellationToken)
        => updateRefreshOperations.RunUpdateAsync(dryRun, stopContainers, limaRecreate, showHelp, cancellationToken);

    public Task<int> RunRefreshAsync(bool rebuild, bool showHelp, CancellationToken cancellationToken)
        => updateRefreshOperations.RunRefreshAsync(rebuild, showHelp, cancellationToken);

    public Task<int> RunUninstallAsync(
        bool dryRun,
        bool removeContainers,
        bool removeVolumes,
        bool showHelp,
        CancellationToken cancellationToken)
        => uninstallOperations.RunUninstallAsync(dryRun, removeContainers, removeVolumes, showHelp, cancellationToken);
}
