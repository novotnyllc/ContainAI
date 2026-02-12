namespace ContainAI.Cli.Host.ContainerRuntime.Infrastructure;

internal interface IContainerRuntimeFileSystemService
{
    Task<bool> IsSymlinkAsync(string path);

    Task<string?> ReadLinkTargetAsync(string path);

    Task<string?> TryReadTrimmedTextAsync(string path);

    Task WriteTimestampAsync(string path);

    void EnsureFileWithContent(string path, string? content);

    bool IsExecutable(string path);
}
