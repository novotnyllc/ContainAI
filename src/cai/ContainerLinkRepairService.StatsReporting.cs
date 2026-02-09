namespace ContainAI.Cli.Host;

internal sealed partial class ContainerLinkRepairService
{
    private async Task LogInfoAsync(bool quiet, string message)
    {
        if (quiet)
        {
            return;
        }

        await stdout.WriteLineAsync(message).ConfigureAwait(false);
    }

    private async Task WriteSummaryAsync(ContainerLinkRepairMode mode, LinkRepairStats stats, bool quiet)
    {
        if (quiet)
        {
            return;
        }

        await stdout.WriteLineAsync().ConfigureAwait(false);
        await stdout.WriteLineAsync(mode == ContainerLinkRepairMode.DryRun ? "=== Dry-Run Summary ===" : "=== Link Status Summary ===").ConfigureAwait(false);
        await stdout.WriteLineAsync($"  OK:      {stats.Ok}").ConfigureAwait(false);
        await stdout.WriteLineAsync($"  Broken:  {stats.Broken}").ConfigureAwait(false);
        await stdout.WriteLineAsync($"  Missing: {stats.Missing}").ConfigureAwait(false);
        if (mode == ContainerLinkRepairMode.Fix)
        {
            await stdout.WriteLineAsync($"  Fixed:   {stats.Fixed}").ConfigureAwait(false);
        }
        else if (mode == ContainerLinkRepairMode.DryRun)
        {
            await stdout.WriteLineAsync($"  Would fix: {stats.Fixed}").ConfigureAwait(false);
        }

        await stdout.WriteLineAsync($"  Errors:  {stats.Errors}").ConfigureAwait(false);
    }

    private sealed record LinkRepairStats
    {
        public int Ok { get; set; }
        public int Broken { get; set; }
        public int Missing { get; set; }
        public int Fixed { get; set; }
        public int Errors { get; set; }
    }
}
