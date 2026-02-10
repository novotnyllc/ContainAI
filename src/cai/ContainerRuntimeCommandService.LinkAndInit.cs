namespace ContainAI.Cli.Host.ContainerRuntime.Infrastructure;

using ContainAI.Cli.Host.ContainerRuntime.Models;

internal interface IContainerRuntimeExecutionContext
{
    TextWriter StandardOutput { get; }

    TextWriter StandardError { get; }

    IManifestTomlParser ManifestTomlParser { get; }

    Task LogInfoAsync(bool quiet, string message);

    Task RunAsRootAsync(string executable, IReadOnlyList<string> arguments);

    Task<ProcessCaptureResult> RunAsRootCaptureAsync(
        string executable,
        IReadOnlyList<string> arguments,
        string? standardInput,
        CancellationToken cancellationToken);

    Task<ProcessCaptureResult> RunProcessCaptureAsync(
        string executable,
        IReadOnlyList<string> arguments,
        string? workingDirectory,
        CancellationToken cancellationToken,
        string? standardInput = null);

    Task<bool> IsSymlinkAsync(string path);

    Task<string?> ReadLinkTargetAsync(string path);

    Task<string?> TryReadTrimmedTextAsync(string path);

    Task WriteTimestampAsync(string path);

    void EnsureFileWithContent(string path, string? content);

    bool IsExecutable(string path);
}

internal sealed class ContainerRuntimeExecutionContext : IContainerRuntimeExecutionContext
{
    public ContainerRuntimeExecutionContext(TextWriter standardOutput, TextWriter standardError, IManifestTomlParser manifestTomlParser)
    {
        StandardOutput = standardOutput;
        StandardError = standardError;
        ManifestTomlParser = manifestTomlParser ?? throw new ArgumentNullException(nameof(manifestTomlParser));
    }

    public TextWriter StandardOutput { get; }

    public TextWriter StandardError { get; }

    public IManifestTomlParser ManifestTomlParser { get; }

    public Task LogInfoAsync(bool quiet, string message)
    {
        if (quiet)
        {
            return Task.CompletedTask;
        }

        return StandardOutput.WriteLineAsync($"[INFO] {message}");
    }

    public Task RunAsRootAsync(string executable, IReadOnlyList<string> arguments)
        => RunAsRootCaptureAsync(executable, arguments, null, CancellationToken.None);

    public async Task<ProcessCaptureResult> RunAsRootCaptureAsync(
        string executable,
        IReadOnlyList<string> arguments,
        string? standardInput,
        CancellationToken cancellationToken)
    {
        if (IsRunningAsRoot())
        {
            var direct = await RunProcessCaptureAsync(executable, arguments, null, cancellationToken, standardInput).ConfigureAwait(false);
            if (direct.ExitCode != 0)
            {
                throw new InvalidOperationException($"Command failed: {executable} {string.Join(' ', arguments)}: {direct.StandardError.Trim()}");
            }

            return direct;
        }

        var sudoArguments = new List<string>(capacity: arguments.Count + 2)
        {
            "-n",
            executable,
        };

        foreach (var argument in arguments)
        {
            sudoArguments.Add(argument);
        }

        var sudo = await RunProcessCaptureAsync("sudo", sudoArguments, null, cancellationToken, standardInput).ConfigureAwait(false);
        if (sudo.ExitCode != 0)
        {
            throw new InvalidOperationException($"sudo command failed for {executable}: {sudo.StandardError.Trim()}");
        }

        return sudo;
    }

    public async Task<ProcessCaptureResult> RunProcessCaptureAsync(
        string executable,
        IReadOnlyList<string> arguments,
        string? workingDirectory,
        CancellationToken cancellationToken,
        string? standardInput = null)
    {
        var result = await CliWrapProcessRunner
            .RunCaptureAsync(executable, arguments, cancellationToken, workingDirectory, standardInput)
            .ConfigureAwait(false);

        return new ProcessCaptureResult(result.ExitCode, result.StandardOutput, result.StandardError);
    }

    public async Task<bool> IsSymlinkAsync(string path)
    {
        var result = await RunProcessCaptureAsync("test", ["-L", path], null, CancellationToken.None).ConfigureAwait(false);
        return result.ExitCode == 0;
    }

    public async Task<string?> ReadLinkTargetAsync(string path)
    {
        var result = await RunProcessCaptureAsync("readlink", [path], null, CancellationToken.None).ConfigureAwait(false);
        if (result.ExitCode != 0)
        {
            return null;
        }

        return result.StandardOutput.Trim();
    }

    public async Task<string?> TryReadTrimmedTextAsync(string path)
    {
        try
        {
            return (await File.ReadAllTextAsync(path).ConfigureAwait(false)).Trim();
        }
        catch (IOException)
        {
            return null;
        }
        catch (UnauthorizedAccessException)
        {
            return null;
        }
    }

    public async Task WriteTimestampAsync(string path)
    {
        var directory = Path.GetDirectoryName(path);
        if (!string.IsNullOrWhiteSpace(directory))
        {
            Directory.CreateDirectory(directory);
        }

        var temporaryPath = $"{path}.tmp.{Environment.ProcessId}";
        var timestamp = DateTimeOffset.UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", System.Globalization.CultureInfo.InvariantCulture) + Environment.NewLine;
        await File.WriteAllTextAsync(temporaryPath, timestamp).ConfigureAwait(false);
        File.Move(temporaryPath, path, overwrite: true);
    }

    public void EnsureFileWithContent(string path, string? content)
    {
        var directory = Path.GetDirectoryName(path);
        if (!string.IsNullOrWhiteSpace(directory))
        {
            Directory.CreateDirectory(directory);
        }

        if (!File.Exists(path))
        {
            using (File.Create(path))
            {
            }
        }

        if (content is not null && new FileInfo(path).Length == 0)
        {
            File.WriteAllText(path, content);
        }
    }

    public bool IsExecutable(string path)
    {
        try
        {
            if (OperatingSystem.IsWindows())
            {
                var extension = Path.GetExtension(path);
                return extension.Equals(".exe", StringComparison.OrdinalIgnoreCase)
                    || extension.Equals(".cmd", StringComparison.OrdinalIgnoreCase)
                    || extension.Equals(".bat", StringComparison.OrdinalIgnoreCase)
                    || extension.Equals(".com", StringComparison.OrdinalIgnoreCase)
                    || extension.Equals(".ps1", StringComparison.OrdinalIgnoreCase);
            }

            var mode = File.GetUnixFileMode(path);
            return (mode & (UnixFileMode.UserExecute | UnixFileMode.GroupExecute | UnixFileMode.OtherExecute)) != 0;
        }
        catch (IOException)
        {
            return false;
        }
        catch (UnauthorizedAccessException)
        {
            return false;
        }
        catch (ArgumentException)
        {
            return false;
        }
        catch (PlatformNotSupportedException)
        {
            return false;
        }
        catch (NotSupportedException)
        {
            return false;
        }
    }

    private static bool IsRunningAsRoot()
    {
        try
        {
            return string.Equals(Environment.UserName, "root", StringComparison.Ordinal);
        }
        catch (InvalidOperationException)
        {
            return false;
        }
        catch (PlatformNotSupportedException)
        {
            return false;
        }
        catch (NotSupportedException)
        {
            return false;
        }
    }
}
