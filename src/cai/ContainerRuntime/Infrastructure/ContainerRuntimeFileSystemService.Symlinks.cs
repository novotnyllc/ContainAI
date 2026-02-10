namespace ContainAI.Cli.Host.ContainerRuntime.Infrastructure;

internal sealed partial class ContainerRuntimeFileSystemService
{
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
}
