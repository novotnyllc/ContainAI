namespace ContainAI.Cli.Host.Devcontainer.ProcessExecution;

internal interface IDevcontainerProcessCommandProbe
{
    Task<bool> CommandExistsAsync(string command, CancellationToken cancellationToken);

    Task<bool> CommandSucceedsAsync(string executable, IReadOnlyList<string> arguments, CancellationToken cancellationToken);
}

internal sealed class DevcontainerProcessCommandProbe : IDevcontainerProcessCommandProbe
{
    private readonly Func<string, IReadOnlyList<string>, CancellationToken, Task<DevcontainerProcessResult>> runProcessCaptureAsync;

    public DevcontainerProcessCommandProbe(Func<string, IReadOnlyList<string>, CancellationToken, Task<DevcontainerProcessResult>> runProcessCaptureAsync)
        => this.runProcessCaptureAsync = runProcessCaptureAsync ?? throw new ArgumentNullException(nameof(runProcessCaptureAsync));

    public async Task<bool> CommandExistsAsync(string command, CancellationToken cancellationToken)
    {
        var result = await runProcessCaptureAsync("sh", ["-c", $"command -v {command} >/dev/null 2>&1"], cancellationToken).ConfigureAwait(false);
        return result.ExitCode == 0;
    }

    public async Task<bool> CommandSucceedsAsync(string executable, IReadOnlyList<string> arguments, CancellationToken cancellationToken)
    {
        var result = await runProcessCaptureAsync(executable, arguments, cancellationToken).ConfigureAwait(false);
        return result.ExitCode == 0;
    }
}
