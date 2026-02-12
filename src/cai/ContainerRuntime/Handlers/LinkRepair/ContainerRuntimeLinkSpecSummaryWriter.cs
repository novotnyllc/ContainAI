using ContainAI.Cli.Host.ContainerRuntime.Infrastructure;
using ContainAI.Cli.Host.ContainerRuntime.Models;

namespace ContainAI.Cli.Host.ContainerRuntime.Handlers;

internal sealed class ContainerRuntimeLinkSpecSummaryWriter(
    IContainerRuntimeExecutionContext context) : IContainerRuntimeLinkSpecSummaryWriter
{
    public async Task WriteSummaryAsync(LinkRepairMode mode, LinkRepairStats stats, bool quiet)
    {
        if (quiet)
        {
            return;
        }

        await context.StandardOutput.WriteLineAsync().ConfigureAwait(false);
        await context.StandardOutput.WriteLineAsync(mode == LinkRepairMode.DryRun ? "=== Dry-Run Summary ===" : "=== Link Status Summary ===").ConfigureAwait(false);
        await context.StandardOutput.WriteLineAsync($"  OK:      {stats.Ok}").ConfigureAwait(false);
        await context.StandardOutput.WriteLineAsync($"  Broken:  {stats.Broken}").ConfigureAwait(false);
        await context.StandardOutput.WriteLineAsync($"  Missing: {stats.Missing}").ConfigureAwait(false);
        if (mode == LinkRepairMode.Fix)
        {
            await context.StandardOutput.WriteLineAsync($"  Fixed:   {stats.Fixed}").ConfigureAwait(false);
        }
        else if (mode == LinkRepairMode.DryRun)
        {
            await context.StandardOutput.WriteLineAsync($"  Would fix: {stats.Fixed}").ConfigureAwait(false);
        }

        await context.StandardOutput.WriteLineAsync($"  Errors:  {stats.Errors}").ConfigureAwait(false);
    }
}
