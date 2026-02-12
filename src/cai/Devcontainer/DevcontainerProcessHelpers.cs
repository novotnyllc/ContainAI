using ContainAI.Cli.Host.Devcontainer.Inspection;
using ContainAI.Cli.Host.Devcontainer.ProcessExecution;

namespace ContainAI.Cli.Host.Devcontainer;

internal sealed class DevcontainerProcessHelpers : IDevcontainerProcessHelpers
{
    private readonly IDevcontainerProcessExecution processExecution;
    private readonly IDevcontainerFileAndProcessInspection fileAndProcessInspection;
    private readonly IDevcontainerPortUsageInspection portUsageInspection;

    public DevcontainerProcessHelpers()
        : this(
            new DevcontainerFileSystem(),
            new DevcontainerPortInspector(),
            new DevcontainerProcessCaptureRunner(),
            () => Environment.UserName)
    {
    }

    internal DevcontainerProcessHelpers(
        DevcontainerFileSystem fileSystem,
        DevcontainerPortInspector portInspector,
        DevcontainerProcessCaptureRunner processCaptureRunner,
        Func<string> userNameProvider)
    {
        ArgumentNullException.ThrowIfNull(fileSystem);
        ArgumentNullException.ThrowIfNull(portInspector);
        ArgumentNullException.ThrowIfNull(processCaptureRunner);
        ArgumentNullException.ThrowIfNull(userNameProvider);

        var processExecution = new DevcontainerProcessExecution(fileSystem, processCaptureRunner, userNameProvider);
        this.processExecution = processExecution;
        fileAndProcessInspection = new DevcontainerFileAndProcessInspection(fileSystem, processExecution);
        portUsageInspection = new DevcontainerPortUsageInspection(portInspector);
    }

    internal DevcontainerProcessHelpers(
        IDevcontainerProcessExecution processExecution,
        IDevcontainerFileAndProcessInspection fileAndProcessInspection,
        IDevcontainerPortUsageInspection portUsageInspection)
    {
        this.processExecution = processExecution ?? throw new ArgumentNullException(nameof(processExecution));
        this.fileAndProcessInspection = fileAndProcessInspection ?? throw new ArgumentNullException(nameof(fileAndProcessInspection));
        this.portUsageInspection = portUsageInspection ?? throw new ArgumentNullException(nameof(portUsageInspection));
    }

    public bool IsProcessAlive(int processId) => processExecution.IsProcessAlive(processId);

    public Task<bool> CommandExistsAsync(string command, CancellationToken cancellationToken)
        => processExecution.CommandExistsAsync(command, cancellationToken);

    public Task<bool> CommandSucceedsAsync(string executable, IReadOnlyList<string> arguments, CancellationToken cancellationToken)
        => processExecution.CommandSucceedsAsync(executable, arguments, cancellationToken);

    public Task RunAsRootAsync(string executable, IReadOnlyList<string> arguments, CancellationToken cancellationToken)
        => processExecution.RunAsRootAsync(executable, arguments, cancellationToken);

    public Task<DevcontainerProcessResult> RunProcessCaptureAsync(string executable, IReadOnlyList<string> arguments, CancellationToken cancellationToken)
        => processExecution.RunProcessCaptureAsync(executable, arguments, cancellationToken);

    public bool IsPortInUse(string portValue)
        => portUsageInspection.IsPortInUse(portValue);

    public bool IsSymlink(string path)
        => fileAndProcessInspection.IsSymlink(path);

    public Task<bool> IsSshdRunningFromPidFileAsync(string pidFilePath, CancellationToken cancellationToken)
        => fileAndProcessInspection.IsSshdRunningFromPidFileAsync(pidFilePath, cancellationToken);

    public Task<bool> IsSysboxFsMountedAsync(CancellationToken cancellationToken)
        => fileAndProcessInspection.IsSysboxFsMountedAsync(cancellationToken);

    public Task<bool> HasUidMappingIsolationAsync(CancellationToken cancellationToken)
        => fileAndProcessInspection.HasUidMappingIsolationAsync(cancellationToken);
}

internal readonly record struct DevcontainerProcessResult(int ExitCode, string StandardOutput, string StandardError);
