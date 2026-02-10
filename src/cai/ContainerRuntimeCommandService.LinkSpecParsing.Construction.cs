using ContainAI.Cli.Host.ContainerRuntime.Infrastructure;

namespace ContainAI.Cli.Host.ContainerRuntime.Handlers;

internal sealed partial class ContainerRuntimeLinkSpecProcessor : IContainerRuntimeLinkSpecProcessor
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
}
