namespace ContainAI.Cli.Host.Devcontainer.ProcessExecution;

internal sealed class DevcontainerRootCommandExecutor : IDevcontainerRootCommandExecutor
{
    private readonly Func<string, IReadOnlyList<string>, CancellationToken, Task<DevcontainerProcessResult>> runProcessCaptureAsync;
    private readonly Func<string> userNameProvider;
    private readonly IDevcontainerProcessCommandProbe commandProbe;

    public DevcontainerRootCommandExecutor(
        Func<string, IReadOnlyList<string>, CancellationToken, Task<DevcontainerProcessResult>> runProcessCaptureAsync,
        Func<string> userNameProvider,
        IDevcontainerProcessCommandProbe commandProbe)
    {
        this.runProcessCaptureAsync = runProcessCaptureAsync ?? throw new ArgumentNullException(nameof(runProcessCaptureAsync));
        this.userNameProvider = userNameProvider ?? throw new ArgumentNullException(nameof(userNameProvider));
        this.commandProbe = commandProbe ?? throw new ArgumentNullException(nameof(commandProbe));
    }

    public async Task RunAsRootAsync(string executable, IReadOnlyList<string> arguments, CancellationToken cancellationToken)
    {
        if (IsRunningAsRoot())
        {
            var direct = await runProcessCaptureAsync(executable, arguments, cancellationToken).ConfigureAwait(false);
            if (direct.ExitCode != 0)
            {
                throw new InvalidOperationException(direct.StandardError.Trim());
            }

            return;
        }

        if (!await commandProbe.CommandSucceedsAsync("sudo", ["-n", "true"], cancellationToken).ConfigureAwait(false))
        {
            throw new InvalidOperationException($"Root privileges required for command: {executable}");
        }

        var sudoArgs = new List<string>(arguments.Count + 2) { "-n", executable };
        foreach (var argument in arguments)
        {
            sudoArgs.Add(argument);
        }

        var sudoResult = await runProcessCaptureAsync("sudo", sudoArgs, cancellationToken).ConfigureAwait(false);
        if (sudoResult.ExitCode != 0)
        {
            throw new InvalidOperationException(sudoResult.StandardError.Trim());
        }
    }

    private bool IsRunningAsRoot() => string.Equals(userNameProvider(), "root", StringComparison.Ordinal);
}
