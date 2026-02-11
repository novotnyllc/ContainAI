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

    public Task<string?> TryReadTrimmedTextAsync(string path)
        => ContainerRuntimeTextReadService.TryReadTrimmedTextAsync(path);

    public Task WriteTimestampAsync(string path)
        => ContainerRuntimeTimestampWriter.WriteTimestampAsync(path);

    public void EnsureFileWithContent(string path, string? content)
        => ContainerRuntimeFileInitializer.EnsureFileWithContent(path, content);

    public bool IsExecutable(string path)
        => ContainerRuntimeExecutableProbe.IsExecutable(path);
}
