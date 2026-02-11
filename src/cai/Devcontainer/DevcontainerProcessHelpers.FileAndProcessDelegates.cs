namespace ContainAI.Cli.Host;

internal sealed partial class DevcontainerProcessHelpers
{
    public bool IsSymlink(string path)
        => fileAndProcessInspection.IsSymlink(path);

    public Task<bool> IsSshdRunningFromPidFileAsync(string pidFilePath, CancellationToken cancellationToken)
        => fileAndProcessInspection.IsSshdRunningFromPidFileAsync(pidFilePath, cancellationToken);

    public Task<bool> IsSysboxFsMountedAsync(CancellationToken cancellationToken)
        => fileAndProcessInspection.IsSysboxFsMountedAsync(cancellationToken);

    public Task<bool> HasUidMappingIsolationAsync(CancellationToken cancellationToken)
        => fileAndProcessInspection.HasUidMappingIsolationAsync(cancellationToken);
}
