using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed class CaiMaintenanceOperations
{
    private readonly CaiExportOperations exportOperations;
    private readonly CaiSyncOperations syncOperations;
    private readonly CaiLinksOperations linksOperations;
    private readonly CaiUpdateOperations updateOperations;
    private readonly CaiRefreshOperations refreshOperations;
    private readonly CaiUninstallOperations uninstallOperations;

    public CaiMaintenanceOperations(
        TextWriter standardOutput,
        TextWriter standardError,
        ContainerLinkRepairService containerLinkRepairService,
        Func<bool, bool, bool, CancellationToken, Task<int>> runDoctorAsync)
    {
        exportOperations = new CaiExportOperations(standardOutput, standardError);
        syncOperations = new CaiSyncOperations(standardOutput, standardError);
        linksOperations = new CaiLinksOperations(standardOutput, standardError, containerLinkRepairService);

        var baseImageResolver = new CaiBaseImageResolver();
        var imagePuller = new CaiDockerImagePuller();
        var templateRebuilder = new CaiTemplateRebuilder(standardOutput, standardError);
        refreshOperations = new CaiRefreshOperations(
            standardOutput,
            standardError,
            baseImageResolver,
            imagePuller,
            templateRebuilder);

        var containerStopper = new CaiManagedContainerStopper();
        var limaVmRecreator = new CaiLimaVmRecreator(standardOutput, standardError);
        updateOperations = new CaiUpdateOperations(
            standardOutput,
            standardError,
            refreshOperations,
            containerStopper,
            limaVmRecreator,
            runDoctorAsync);

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
        => updateOperations.RunUpdateAsync(dryRun, stopContainers, limaRecreate, showHelp, cancellationToken);

    public Task<int> RunRefreshAsync(bool rebuild, bool showHelp, CancellationToken cancellationToken)
        => refreshOperations.RunRefreshAsync(rebuild, showHelp, cancellationToken);

    public Task<int> RunUninstallAsync(
        bool dryRun,
        bool removeContainers,
        bool removeVolumes,
        bool showHelp,
        CancellationToken cancellationToken)
        => uninstallOperations.RunUninstallAsync(dryRun, removeContainers, removeVolumes, showHelp, cancellationToken);
}
