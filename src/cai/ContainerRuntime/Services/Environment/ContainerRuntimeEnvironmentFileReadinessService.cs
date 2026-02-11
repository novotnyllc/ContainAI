using ContainAI.Cli.Host.ContainerRuntime.Infrastructure;

namespace ContainAI.Cli.Host.ContainerRuntime.Services;

internal interface IContainerRuntimeEnvironmentFileReadinessService
{
    Task<bool> CanLoadAsync(string envFilePath);
}

internal sealed class ContainerRuntimeEnvironmentFileReadinessService(
    IContainerRuntimeExecutionContext context) : IContainerRuntimeEnvironmentFileReadinessService
{
    public async Task<bool> CanLoadAsync(string envFilePath)
    {
        if (await context.IsSymlinkAsync(envFilePath).ConfigureAwait(false))
        {
            await context.StandardError.WriteLineAsync("[WARN] .env is symlink - skipping").ConfigureAwait(false);
            return false;
        }

        if (!File.Exists(envFilePath))
        {
            return false;
        }

        try
        {
            using var stream = File.OpenRead(envFilePath);
            return true;
        }
        catch (IOException)
        {
            await context.StandardError.WriteLineAsync("[WARN] .env unreadable - skipping").ConfigureAwait(false);
            return false;
        }
        catch (UnauthorizedAccessException)
        {
            await context.StandardError.WriteLineAsync("[WARN] .env unreadable - skipping").ConfigureAwait(false);
            return false;
        }
    }
}
