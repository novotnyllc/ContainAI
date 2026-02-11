namespace ContainAI.Cli.Host;

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

internal sealed partial class DevcontainerProcessHelpers : IDevcontainerProcessHelpers
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
}

internal readonly record struct DevcontainerProcessResult(int ExitCode, string StandardOutput, string StandardError);
