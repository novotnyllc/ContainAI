namespace ContainAI.Cli.Host.Devcontainer.Inspection;

internal interface IDevcontainerFileAndProcessInspection
{
    bool IsSymlink(string path);

    Task<bool> IsSshdRunningFromPidFileAsync(string pidFilePath, CancellationToken cancellationToken);

    Task<bool> IsSysboxFsMountedAsync(CancellationToken cancellationToken);

    Task<bool> HasUidMappingIsolationAsync(CancellationToken cancellationToken);
}
