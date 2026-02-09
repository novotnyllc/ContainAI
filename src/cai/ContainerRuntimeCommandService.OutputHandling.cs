namespace ContainAI.Cli.Host;

internal sealed partial class ContainerRuntimeCommandService
{
    private async Task<int> WriteInitErrorAsync(Exception exception)
    {
        await stderr.WriteLineAsync($"[ERROR] {exception.Message}").ConfigureAwait(false);
        return 1;
    }

    private async Task WriteUserLinkSpecWarningAsync(LinkRepairStats stats, Exception exception)
    {
        stats.Errors++;
        await stderr.WriteLineAsync($"[WARN] Failed to process user link spec: {exception.Message}").ConfigureAwait(false);
    }

    private async Task<int> WriteLinkRepairErrorAsync(Exception exception)
    {
        await stderr.WriteLineAsync($"ERROR: {exception.Message}").ConfigureAwait(false);
        return 1;
    }
}
