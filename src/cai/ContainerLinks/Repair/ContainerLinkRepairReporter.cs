namespace ContainAI.Cli.Host;

internal sealed class ContainerLinkRepairReporter(TextWriter standardOutput) : IContainerLinkRepairReporter
{
    public async Task LogInfoAsync(bool quiet, string message)
    {
        if (quiet)
        {
            return;
        }

        await standardOutput.WriteLineAsync(message).ConfigureAwait(false);
    }

    public async Task WriteSummaryAsync(ContainerLinkRepairMode mode, ContainerLinkRepairStats stats, bool quiet)
    {
        if (quiet)
        {
            return;
        }

        await standardOutput.WriteLineAsync().ConfigureAwait(false);
        await standardOutput.WriteLineAsync(mode == ContainerLinkRepairMode.DryRun ? "=== Dry-Run Summary ===" : "=== Link Status Summary ===").ConfigureAwait(false);
        await standardOutput.WriteLineAsync($"  OK:      {stats.Ok}").ConfigureAwait(false);
        await standardOutput.WriteLineAsync($"  Broken:  {stats.Broken}").ConfigureAwait(false);
        await standardOutput.WriteLineAsync($"  Missing: {stats.Missing}").ConfigureAwait(false);
        if (mode == ContainerLinkRepairMode.Fix)
        {
            await standardOutput.WriteLineAsync($"  Fixed:   {stats.Fixed}").ConfigureAwait(false);
        }
        else if (mode == ContainerLinkRepairMode.DryRun)
        {
            await standardOutput.WriteLineAsync($"  Would fix: {stats.Fixed}").ConfigureAwait(false);
        }

        await standardOutput.WriteLineAsync($"  Errors:  {stats.Errors}").ConfigureAwait(false);
    }
}
