using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed class CaiMaintenanceCommandHandler
{
    private readonly CaiMaintenanceOperations maintenanceOperations;

    public CaiMaintenanceCommandHandler(CaiMaintenanceOperations caiMaintenanceOperations)
        => maintenanceOperations = caiMaintenanceOperations ?? throw new ArgumentNullException(nameof(caiMaintenanceOperations));

    public Task<int> RunExportAsync(ExportCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return maintenanceOperations.RunExportAsync(options.Output, options.DataVolume, options.Container, options.Workspace, cancellationToken);
    }

    public Task<int> RunSyncAsync(CancellationToken cancellationToken)
        => maintenanceOperations.RunSyncAsync(cancellationToken);

    public Task<int> RunUpdateAsync(UpdateCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return maintenanceOperations.RunUpdateAsync(
            dryRun: options.DryRun,
            stopContainers: options.StopContainers || options.Force,
            limaRecreate: options.LimaRecreate,
            showHelp: false,
            cancellationToken);
    }

    public Task<int> RunRefreshAsync(RefreshCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return maintenanceOperations.RunRefreshAsync(
            rebuild: options.Rebuild,
            showHelp: false,
            cancellationToken);
    }

    public Task<int> RunUninstallAsync(UninstallCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return maintenanceOperations.RunUninstallAsync(
            dryRun: options.DryRun,
            removeContainers: options.Containers,
            removeVolumes: options.Volumes,
            showHelp: false,
            cancellationToken);
    }

    public Task<int> RunLinksCheckAsync(LinksSubcommandOptions options, CancellationToken cancellationToken)
        => RunLinksSubcommandAsync("check", options, cancellationToken);

    public Task<int> RunLinksFixAsync(LinksSubcommandOptions options, CancellationToken cancellationToken)
        => RunLinksSubcommandAsync("fix", options, cancellationToken);

    private Task<int> RunLinksSubcommandAsync(string subcommand, LinksSubcommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        var containerName = string.IsNullOrWhiteSpace(options.Container) ? options.Name : options.Container;
        return maintenanceOperations.RunLinksAsync(subcommand, containerName, options.Workspace, options.DryRun, options.Quiet, cancellationToken);
    }
}
