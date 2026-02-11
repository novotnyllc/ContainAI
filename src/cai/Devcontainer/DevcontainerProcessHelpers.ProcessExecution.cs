namespace ContainAI.Cli.Host;

internal interface IDevcontainerProcessExecution
{
    bool IsProcessAlive(int processId);

    Task<bool> CommandExistsAsync(string command, CancellationToken cancellationToken);

    Task<bool> CommandSucceedsAsync(string executable, IReadOnlyList<string> arguments, CancellationToken cancellationToken);

    Task RunAsRootAsync(string executable, IReadOnlyList<string> arguments, CancellationToken cancellationToken);

    Task<DevcontainerProcessResult> RunProcessCaptureAsync(string executable, IReadOnlyList<string> arguments, CancellationToken cancellationToken);
}

internal sealed partial class DevcontainerProcessExecution : IDevcontainerProcessExecution
{
    private readonly DevcontainerFileSystem fileSystem;
    private readonly DevcontainerProcessCaptureRunner processCaptureRunner;
    private readonly Func<string> userNameProvider;

    public DevcontainerProcessExecution(
        DevcontainerFileSystem fileSystem,
        DevcontainerProcessCaptureRunner processCaptureRunner,
        Func<string> userNameProvider)
    {
        this.fileSystem = fileSystem ?? throw new ArgumentNullException(nameof(fileSystem));
        this.processCaptureRunner = processCaptureRunner ?? throw new ArgumentNullException(nameof(processCaptureRunner));
        this.userNameProvider = userNameProvider ?? throw new ArgumentNullException(nameof(userNameProvider));
    }

    public async Task<DevcontainerProcessResult> RunProcessCaptureAsync(string executable, IReadOnlyList<string> arguments, CancellationToken cancellationToken)
    {
        var result = await processCaptureRunner.RunCaptureAsync(executable, arguments, cancellationToken).ConfigureAwait(false);
        return new DevcontainerProcessResult(result.ExitCode, result.StandardOutput, result.StandardError);
    }
}
