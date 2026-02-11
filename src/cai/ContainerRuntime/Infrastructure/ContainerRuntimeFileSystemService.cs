namespace ContainAI.Cli.Host.ContainerRuntime.Infrastructure;

using System.Globalization;

internal interface IContainerRuntimeFileSystemService
{
    Task<bool> IsSymlinkAsync(string path);

    Task<string?> ReadLinkTargetAsync(string path);

    Task<string?> TryReadTrimmedTextAsync(string path);

    Task WriteTimestampAsync(string path);

    void EnsureFileWithContent(string path, string? content);

    bool IsExecutable(string path);
}

internal sealed class ContainerRuntimeFileSystemService : IContainerRuntimeFileSystemService
{
    private readonly IContainerRuntimeProcessExecutor processExecutor;

    public ContainerRuntimeFileSystemService(IContainerRuntimeProcessExecutor processExecutor)
        => this.processExecutor = processExecutor ?? throw new ArgumentNullException(nameof(processExecutor));

    public async Task<bool> IsSymlinkAsync(string path)
    {
        var result = await processExecutor
            .RunCaptureAsync("test", ["-L", path], null, CancellationToken.None)
            .ConfigureAwait(false);
        return result.ExitCode == 0;
    }

    public async Task<string?> ReadLinkTargetAsync(string path)
    {
        var result = await processExecutor
            .RunCaptureAsync("readlink", [path], null, CancellationToken.None)
            .ConfigureAwait(false);
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
        var timestamp = DateTimeOffset.UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", CultureInfo.InvariantCulture) + Environment.NewLine;
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
}
