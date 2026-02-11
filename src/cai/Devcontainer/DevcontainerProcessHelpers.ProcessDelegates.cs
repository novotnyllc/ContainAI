namespace ContainAI.Cli.Host;

internal sealed partial class DevcontainerProcessHelpers
{
    public bool IsProcessAlive(int processId) => processExecution.IsProcessAlive(processId);

    public Task<bool> CommandExistsAsync(string command, CancellationToken cancellationToken)
        => processExecution.CommandExistsAsync(command, cancellationToken);

    public Task<bool> CommandSucceedsAsync(string executable, IReadOnlyList<string> arguments, CancellationToken cancellationToken)
        => processExecution.CommandSucceedsAsync(executable, arguments, cancellationToken);

    public Task RunAsRootAsync(string executable, IReadOnlyList<string> arguments, CancellationToken cancellationToken)
        => processExecution.RunAsRootAsync(executable, arguments, cancellationToken);

    public Task<DevcontainerProcessResult> RunProcessCaptureAsync(string executable, IReadOnlyList<string> arguments, CancellationToken cancellationToken)
        => processExecution.RunProcessCaptureAsync(executable, arguments, cancellationToken);
}
