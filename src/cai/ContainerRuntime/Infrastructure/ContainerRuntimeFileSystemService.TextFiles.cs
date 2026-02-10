namespace ContainAI.Cli.Host.ContainerRuntime.Infrastructure;

using System.Globalization;

internal sealed partial class ContainerRuntimeFileSystemService
{
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
}
