namespace ContainAI.Cli.Host;

internal interface IDevcontainerFileAndProcessInspection
{
    bool IsSymlink(string path);

    Task<bool> IsSshdRunningFromPidFileAsync(string pidFilePath, CancellationToken cancellationToken);

    Task<bool> IsSysboxFsMountedAsync(CancellationToken cancellationToken);

    Task<bool> HasUidMappingIsolationAsync(CancellationToken cancellationToken);
}

internal sealed partial class DevcontainerFileAndProcessInspection : IDevcontainerFileAndProcessInspection
{
    private readonly DevcontainerFileSystem fileSystem;
    private readonly IDevcontainerProcessExecution processExecution;

    public DevcontainerFileAndProcessInspection(DevcontainerFileSystem fileSystem, IDevcontainerProcessExecution processExecution)
    {
        this.fileSystem = fileSystem ?? throw new ArgumentNullException(nameof(fileSystem));
        this.processExecution = processExecution ?? throw new ArgumentNullException(nameof(processExecution));
    }
}
