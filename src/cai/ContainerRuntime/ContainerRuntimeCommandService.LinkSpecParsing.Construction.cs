using ContainAI.Cli.Host.ContainerRuntime.Infrastructure;
using ContainAI.Cli.Host.ContainerRuntime.Models;

namespace ContainAI.Cli.Host.ContainerRuntime.Handlers;

internal sealed class ContainerRuntimeLinkSpecProcessor : IContainerRuntimeLinkSpecProcessor
{
    private readonly IContainerRuntimeExecutionContext context;
    private readonly IContainerRuntimeLinkSpecFileReader linkSpecFileReader;
    private readonly IContainerRuntimeLinkSpecParser linkSpecParser;
    private readonly IContainerRuntimeLinkSpecEntryProcessor entryProcessor;
    private readonly IContainerRuntimeLinkSpecSummaryWriter summaryWriter;

    public ContainerRuntimeLinkSpecProcessor(IContainerRuntimeExecutionContext context)
        : this(
            context,
            new ContainerRuntimeLinkSpecFileReader(),
            new ContainerRuntimeLinkSpecParser(),
            new ContainerRuntimeLinkSpecEntryProcessor(
                context,
                new ContainerRuntimeLinkSpecEntryValidator(),
                new ContainerRuntimeLinkEntryInspector(context),
                new ContainerRuntimeLinkEntryRepairer(context)),
            new ContainerRuntimeLinkSpecSummaryWriter(context))
    {
    }

    internal ContainerRuntimeLinkSpecProcessor(
        IContainerRuntimeExecutionContext context,
        IContainerRuntimeLinkSpecFileReader linkSpecFileReader,
        IContainerRuntimeLinkSpecParser linkSpecParser,
        IContainerRuntimeLinkSpecEntryProcessor entryProcessor,
        IContainerRuntimeLinkSpecSummaryWriter summaryWriter)
    {
        this.context = context ?? throw new ArgumentNullException(nameof(context));
        this.linkSpecFileReader = linkSpecFileReader ?? throw new ArgumentNullException(nameof(linkSpecFileReader));
        this.linkSpecParser = linkSpecParser ?? throw new ArgumentNullException(nameof(linkSpecParser));
        this.entryProcessor = entryProcessor ?? throw new ArgumentNullException(nameof(entryProcessor));
        this.summaryWriter = summaryWriter ?? throw new ArgumentNullException(nameof(summaryWriter));
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
            await entryProcessor.ProcessEntryAsync(entry, specPath, mode, quiet, stats).ConfigureAwait(false);
        }
    }

    public Task WriteSummaryAsync(LinkRepairMode mode, LinkRepairStats stats, bool quiet)
        => summaryWriter.WriteSummaryAsync(mode, stats, quiet);
}
