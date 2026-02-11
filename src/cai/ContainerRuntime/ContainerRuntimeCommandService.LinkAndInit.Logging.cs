namespace ContainAI.Cli.Host.ContainerRuntime.Infrastructure;

internal sealed partial class ContainerRuntimeExecutionContext
{
    public Task LogInfoAsync(bool quiet, string message)
    {
        if (quiet)
        {
            return Task.CompletedTask;
        }

        return StandardOutput.WriteLineAsync($"[INFO] {message}");
    }
}
