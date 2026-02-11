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

    public bool IsProcessAlive(int processId)
    {
        if (processId <= 0)
        {
            return false;
        }

        try
        {
            if (OperatingSystem.IsLinux() && fileSystem.DirectoryExists($"/proc/{processId}"))
            {
                return true;
            }

            if (OperatingSystem.IsLinux() || OperatingSystem.IsMacOS())
            {
                var result = processCaptureRunner
                    .RunCaptureAsync("kill", ["-0", processId.ToString(System.Globalization.CultureInfo.InvariantCulture)], CancellationToken.None)
                    .GetAwaiter()
                    .GetResult();
                return result.ExitCode == 0;
            }
        }
        catch (InvalidOperationException)
        {
            return false;
        }
        catch (IOException)
        {
            return false;
        }
        catch (NotSupportedException)
        {
            return false;
        }

        return false;
    }

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
