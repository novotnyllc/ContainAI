namespace ContainAI.Cli.Host.ContainerRuntime.Infrastructure;

internal static class ContainerRuntimeTextReadService
{
    public static async Task<string?> TryReadTrimmedTextAsync(string path)
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
}
