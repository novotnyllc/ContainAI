namespace ContainAI.Cli.Host;

internal sealed partial class DevcontainerProcessExecution
{
    public async Task RunAsRootAsync(string executable, IReadOnlyList<string> arguments, CancellationToken cancellationToken)
    {
        if (IsRunningAsRoot())
        {
            var direct = await RunProcessCaptureAsync(executable, arguments, cancellationToken).ConfigureAwait(false);
            if (direct.ExitCode != 0)
            {
                throw new InvalidOperationException(direct.StandardError.Trim());
            }

            return;
        }

        if (!await CommandSucceedsAsync("sudo", ["-n", "true"], cancellationToken).ConfigureAwait(false))
        {
            throw new InvalidOperationException($"Root privileges required for command: {executable}");
        }

        var sudoArgs = new List<string>(arguments.Count + 2) { "-n", executable };
        foreach (var argument in arguments)
        {
            sudoArgs.Add(argument);
        }

        var sudoResult = await RunProcessCaptureAsync("sudo", sudoArgs, cancellationToken).ConfigureAwait(false);
        if (sudoResult.ExitCode != 0)
        {
            throw new InvalidOperationException(sudoResult.StandardError.Trim());
        }
    }

    private bool IsRunningAsRoot() => string.Equals(userNameProvider(), "root", StringComparison.Ordinal);
}
