namespace ContainAI.Cli.Host;

internal interface IDevcontainerProcessExecution
{
    bool IsProcessAlive(int processId);

    Task<bool> CommandExistsAsync(string command, CancellationToken cancellationToken);

    Task<bool> CommandSucceedsAsync(string executable, IReadOnlyList<string> arguments, CancellationToken cancellationToken);

    Task RunAsRootAsync(string executable, IReadOnlyList<string> arguments, CancellationToken cancellationToken);

    Task<DevcontainerProcessResult> RunProcessCaptureAsync(string executable, IReadOnlyList<string> arguments, CancellationToken cancellationToken);
}

internal sealed class DevcontainerProcessExecution : IDevcontainerProcessExecution
{
    private readonly DevcontainerProcessCaptureRunner processCaptureRunner;
    private readonly IDevcontainerProcessCommandProbe commandProbe;
    private readonly IDevcontainerProcessLivenessChecker livenessChecker;
    private readonly IDevcontainerRootCommandExecutor rootCommandExecutor;

    public DevcontainerProcessExecution(
        DevcontainerFileSystem fileSystem,
        DevcontainerProcessCaptureRunner processCaptureRunner,
        Func<string> userNameProvider)
        : this(
            processCaptureRunner,
            CreateCommandProbe(processCaptureRunner),
            new DevcontainerProcessLivenessChecker(fileSystem, processCaptureRunner),
            CreateRootCommandExecutor(processCaptureRunner, userNameProvider))
    {
    }

    internal DevcontainerProcessExecution(
        DevcontainerProcessCaptureRunner processCaptureRunner,
        IDevcontainerProcessCommandProbe devcontainerProcessCommandProbe,
        IDevcontainerProcessLivenessChecker devcontainerProcessLivenessChecker,
        IDevcontainerRootCommandExecutor devcontainerRootCommandExecutor)
    {
        this.processCaptureRunner = processCaptureRunner ?? throw new ArgumentNullException(nameof(processCaptureRunner));
        commandProbe = devcontainerProcessCommandProbe ?? throw new ArgumentNullException(nameof(devcontainerProcessCommandProbe));
        livenessChecker = devcontainerProcessLivenessChecker ?? throw new ArgumentNullException(nameof(devcontainerProcessLivenessChecker));
        rootCommandExecutor = devcontainerRootCommandExecutor ?? throw new ArgumentNullException(nameof(devcontainerRootCommandExecutor));
    }

    public async Task<DevcontainerProcessResult> RunProcessCaptureAsync(string executable, IReadOnlyList<string> arguments, CancellationToken cancellationToken)
    {
        var result = await processCaptureRunner.RunCaptureAsync(executable, arguments, cancellationToken).ConfigureAwait(false);
        return new DevcontainerProcessResult(result.ExitCode, result.StandardOutput, result.StandardError);
    }

    public async Task<bool> CommandExistsAsync(string command, CancellationToken cancellationToken)
        => await commandProbe.CommandExistsAsync(command, cancellationToken).ConfigureAwait(false);

    public async Task<bool> CommandSucceedsAsync(string executable, IReadOnlyList<string> arguments, CancellationToken cancellationToken)
        => await commandProbe.CommandSucceedsAsync(executable, arguments, cancellationToken).ConfigureAwait(false);

    public bool IsProcessAlive(int processId)
        => livenessChecker.IsProcessAlive(processId);

    public async Task RunAsRootAsync(string executable, IReadOnlyList<string> arguments, CancellationToken cancellationToken)
        => await rootCommandExecutor.RunAsRootAsync(executable, arguments, cancellationToken).ConfigureAwait(false);

    private static DevcontainerRootCommandExecutor CreateRootCommandExecutor(
        DevcontainerProcessCaptureRunner processCaptureRunner,
        Func<string> userNameProvider)
    {
        ArgumentNullException.ThrowIfNull(processCaptureRunner);
        ArgumentNullException.ThrowIfNull(userNameProvider);
        var processResultRunner = CreateProcessResultRunner(processCaptureRunner);
        var commandProbe = new DevcontainerProcessCommandProbe(processResultRunner);
        return new DevcontainerRootCommandExecutor(
            processResultRunner,
            userNameProvider,
            commandProbe);
    }

    private static DevcontainerProcessCommandProbe CreateCommandProbe(DevcontainerProcessCaptureRunner processCaptureRunner)
        => new(CreateProcessResultRunner(processCaptureRunner));

    private static Func<string, IReadOnlyList<string>, CancellationToken, Task<DevcontainerProcessResult>> CreateProcessResultRunner(
        DevcontainerProcessCaptureRunner processCaptureRunner)
    {
        ArgumentNullException.ThrowIfNull(processCaptureRunner);
        return async (executable, arguments, cancellationToken) =>
        {
            var result = await processCaptureRunner
                .RunCaptureAsync(executable, arguments, cancellationToken)
                .ConfigureAwait(false);
            return new DevcontainerProcessResult(result.ExitCode, result.StandardOutput, result.StandardError);
        };
    }
}
