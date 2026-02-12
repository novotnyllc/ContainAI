using ContainAI.Cli.Host.Devcontainer.ProcessExecution;

namespace ContainAI.Cli.Host.Devcontainer;

internal interface IDevcontainerProcessHelpers
{
    bool IsProcessAlive(int processId);

    Task<bool> CommandExistsAsync(string command, CancellationToken cancellationToken);

    Task<bool> CommandSucceedsAsync(string executable, IReadOnlyList<string> arguments, CancellationToken cancellationToken);

    Task RunAsRootAsync(string executable, IReadOnlyList<string> arguments, CancellationToken cancellationToken);

    Task<DevcontainerProcessResult> RunProcessCaptureAsync(string executable, IReadOnlyList<string> arguments, CancellationToken cancellationToken);

    bool IsPortInUse(string portValue);

    bool IsSymlink(string path);

    Task<bool> IsSshdRunningFromPidFileAsync(string pidFilePath, CancellationToken cancellationToken);

    Task<bool> IsSysboxFsMountedAsync(CancellationToken cancellationToken);

    Task<bool> HasUidMappingIsolationAsync(CancellationToken cancellationToken);
}
