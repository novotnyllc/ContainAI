using ContainAI.Cli.Host.ContainerRuntime.Infrastructure;
using ContainAI.Cli.Host.ContainerRuntime.Models;

namespace ContainAI.Cli.Host.ContainerRuntime.Handlers;

internal sealed class ContainerRuntimeLinkSpecProcessor : IContainerRuntimeLinkSpecProcessor
{
    private readonly IContainerRuntimeExecutionContext context;
    private readonly IContainerRuntimeLinkSpecFileReader linkSpecFileReader;
    private readonly IContainerRuntimeLinkSpecParser linkSpecParser;
    private readonly IContainerRuntimeLinkSpecEntryValidator linkSpecEntryValidator;
    private readonly IContainerRuntimeLinkEntryInspector linkEntryInspector;
    private readonly IContainerRuntimeLinkEntryRepairer linkEntryRepairer;

    public ContainerRuntimeLinkSpecProcessor(IContainerRuntimeExecutionContext context)
        : this(
            context,
            new ContainerRuntimeLinkSpecFileReader(),
            new ContainerRuntimeLinkSpecParser(),
            new ContainerRuntimeLinkSpecEntryValidator(),
            new ContainerRuntimeLinkEntryInspector(context),
            new ContainerRuntimeLinkEntryRepairer(context))
    {
    }

    internal ContainerRuntimeLinkSpecProcessor(
        IContainerRuntimeExecutionContext context,
        IContainerRuntimeLinkSpecFileReader linkSpecFileReader,
        IContainerRuntimeLinkSpecParser linkSpecParser,
        IContainerRuntimeLinkSpecEntryValidator linkSpecEntryValidator,
        IContainerRuntimeLinkEntryInspector linkEntryInspector,
        IContainerRuntimeLinkEntryRepairer linkEntryRepairer)
    {
        this.context = context ?? throw new ArgumentNullException(nameof(context));
        this.linkSpecFileReader = linkSpecFileReader ?? throw new ArgumentNullException(nameof(linkSpecFileReader));
        this.linkSpecParser = linkSpecParser ?? throw new ArgumentNullException(nameof(linkSpecParser));
        this.linkSpecEntryValidator = linkSpecEntryValidator ?? throw new ArgumentNullException(nameof(linkSpecEntryValidator));
        this.linkEntryInspector = linkEntryInspector ?? throw new ArgumentNullException(nameof(linkEntryInspector));
        this.linkEntryRepairer = linkEntryRepairer ?? throw new ArgumentNullException(nameof(linkEntryRepairer));
    }

    public async Task ProcessLinkSpecAsync(
        string specPath,
        LinkRepairMode mode,
        bool quiet,
        string specName,
        LinkRepairStats stats,
        CancellationToken cancellationToken)
    {
        var json = await linkSpecFileReader.ReadAllTextAsync(specPath, cancellationToken).ConfigureAwait(false);
        var entries = linkSpecParser.ParseEntries(specPath, json);

        await context.LogInfoAsync(quiet, $"Processing {specName} ({entries.Count} links)").ConfigureAwait(false);

        foreach (var entry in entries)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (!linkSpecEntryValidator.TryValidate(entry, out var validatedEntry))
            {
                stats.Errors++;
                await context.StandardError.WriteLineAsync($"[WARN] Skipping invalid link spec entry in {specPath}").ConfigureAwait(false);
                continue;
            }

            await ProcessValidatedEntryAsync(validatedEntry, mode, quiet, stats).ConfigureAwait(false);
        }
    }

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

    private async Task ProcessValidatedEntryAsync(ContainerRuntimeLinkSpecValidatedEntry validatedEntry, LinkRepairMode mode, bool quiet, LinkRepairStats stats)
    {
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
