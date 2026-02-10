namespace ContainAI.Cli.Host;

internal sealed partial class DevcontainerProcessExecution
{
    public async Task<bool> CommandExistsAsync(string command, CancellationToken cancellationToken)
    {
        var result = await RunProcessCaptureAsync("sh", ["-c", $"command -v {command} >/dev/null 2>&1"], cancellationToken).ConfigureAwait(false);
        return result.ExitCode == 0;
    }

    public async Task<bool> CommandSucceedsAsync(string executable, IReadOnlyList<string> arguments, CancellationToken cancellationToken)
    {
        var result = await RunProcessCaptureAsync(executable, arguments, cancellationToken).ConfigureAwait(false);
        return result.ExitCode == 0;
    }
}
