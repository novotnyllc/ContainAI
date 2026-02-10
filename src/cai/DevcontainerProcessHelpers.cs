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
    private readonly DevcontainerFileSystem fileSystem;
    private readonly DevcontainerPortInspector portInspector;
    private readonly DevcontainerProcessCaptureRunner processCaptureRunner;
    private readonly Func<string> userNameProvider;

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
        this.fileSystem = fileSystem ?? throw new ArgumentNullException(nameof(fileSystem));
        this.portInspector = portInspector ?? throw new ArgumentNullException(nameof(portInspector));
        this.processCaptureRunner = processCaptureRunner ?? throw new ArgumentNullException(nameof(processCaptureRunner));
        this.userNameProvider = userNameProvider ?? throw new ArgumentNullException(nameof(userNameProvider));
    }
}

internal readonly record struct DevcontainerProcessResult(int ExitCode, string StandardOutput, string StandardError);
