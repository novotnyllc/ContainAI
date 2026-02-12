using ContainAI.Cli.Host.Devcontainer.ProcessExecution;

namespace ContainAI.Cli.Host.Devcontainer.Inspection;

internal interface IDevcontainerFileAndProcessInspection
{
    bool IsSymlink(string path);

    Task<bool> IsSshdRunningFromPidFileAsync(string pidFilePath, CancellationToken cancellationToken);

    Task<bool> IsSysboxFsMountedAsync(CancellationToken cancellationToken);

    Task<bool> HasUidMappingIsolationAsync(CancellationToken cancellationToken);
}

internal sealed class DevcontainerFileAndProcessInspection : IDevcontainerFileAndProcessInspection
{
    private readonly IDevcontainerSymlinkInspector symlinkInspector;
    private readonly IDevcontainerSshdProcessInspector sshdProcessInspector;
    private readonly IDevcontainerSysboxMountInspector sysboxMountInspector;
    private readonly IDevcontainerUidMappingInspector uidMappingInspector;

    public DevcontainerFileAndProcessInspection(DevcontainerFileSystem fileSystem, IDevcontainerProcessExecution processExecution)
        : this(
            new DevcontainerSymlinkInspector(fileSystem ?? throw new ArgumentNullException(nameof(fileSystem))),
            new DevcontainerSshdProcessInspector(fileSystem, processExecution ?? throw new ArgumentNullException(nameof(processExecution))),
            new DevcontainerSysboxMountInspector(fileSystem),
            new DevcontainerUidMappingInspector(fileSystem))
    {
    }

    internal DevcontainerFileAndProcessInspection(
        IDevcontainerSymlinkInspector devcontainerSymlinkInspector,
        IDevcontainerSshdProcessInspector devcontainerSshdProcessInspector,
        IDevcontainerSysboxMountInspector devcontainerSysboxMountInspector,
        IDevcontainerUidMappingInspector devcontainerUidMappingInspector)
    {
        symlinkInspector = devcontainerSymlinkInspector ?? throw new ArgumentNullException(nameof(devcontainerSymlinkInspector));
        sshdProcessInspector = devcontainerSshdProcessInspector ?? throw new ArgumentNullException(nameof(devcontainerSshdProcessInspector));
        sysboxMountInspector = devcontainerSysboxMountInspector ?? throw new ArgumentNullException(nameof(devcontainerSysboxMountInspector));
        uidMappingInspector = devcontainerUidMappingInspector ?? throw new ArgumentNullException(nameof(devcontainerUidMappingInspector));
    }

    public bool IsSymlink(string path)
        => symlinkInspector.IsSymlink(path);

    public Task<bool> IsSshdRunningFromPidFileAsync(string pidFilePath, CancellationToken cancellationToken)
        => sshdProcessInspector.IsSshdRunningFromPidFileAsync(pidFilePath, cancellationToken);

    public Task<bool> IsSysboxFsMountedAsync(CancellationToken cancellationToken)
        => sysboxMountInspector.IsSysboxFsMountedAsync(cancellationToken);

    public Task<bool> HasUidMappingIsolationAsync(CancellationToken cancellationToken)
        => uidMappingInspector.HasUidMappingIsolationAsync(cancellationToken);
}
