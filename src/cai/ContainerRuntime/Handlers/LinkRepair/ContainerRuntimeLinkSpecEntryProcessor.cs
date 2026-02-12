using ContainAI.Cli.Host.ContainerRuntime.Infrastructure;
using ContainAI.Cli.Host.ContainerRuntime.Models;

namespace ContainAI.Cli.Host.ContainerRuntime.Handlers;

internal sealed class ContainerRuntimeLinkSpecEntryProcessor(
    IContainerRuntimeExecutionContext context,
    IContainerRuntimeLinkSpecEntryValidator linkSpecEntryValidator,
    IContainerRuntimeLinkEntryInspector linkEntryInspector,
    IContainerRuntimeLinkEntryRepairer linkEntryRepairer) : IContainerRuntimeLinkSpecEntryProcessor
{
    public async Task ProcessEntryAsync(
        ContainerRuntimeLinkSpecRawEntry entry,
        string specPath,
        LinkRepairMode mode,
        bool quiet,
        LinkRepairStats stats)
    {
        if (!linkSpecEntryValidator.TryValidate(entry, out var validatedEntry))
        {
            stats.Errors++;
            await context.StandardError.WriteLineAsync($"[WARN] Skipping invalid link spec entry in {specPath}").ConfigureAwait(false);
            return;
        }

        var inspection = await linkEntryInspector
            .InspectAsync(validatedEntry.LinkPath, validatedEntry.TargetPath, validatedEntry.RemoveFirst, quiet, stats)
            .ConfigureAwait(false);
        if (!inspection.RequiresRepair)
        {
            return;
        }

        await linkEntryRepairer
            .RepairAsync(inspection.LinkPath, inspection.TargetPath, inspection.RemoveFirst, mode, quiet, stats)
            .ConfigureAwait(false);
    }
}
