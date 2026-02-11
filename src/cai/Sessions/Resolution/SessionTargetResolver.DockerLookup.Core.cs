namespace ContainAI.Cli.Host;

internal sealed partial class SessionTargetDockerLookupService : ISessionTargetDockerLookupService
{
    private const string LabelInspectFormat =
        "{{index .Config.Labels \"containai.managed\"}}|{{index .Config.Labels \"containai.workspace\"}}|{{index .Config.Labels \"containai.data-volume\"}}|{{index .Config.Labels \"containai.ssh-port\"}}|{{.Config.Image}}|{{.State.Status}}";
    private const int LabelInspectFieldCount = 6;
    private const int MaxContainerNameCollisionAttempts = 99;
    private const int MaxDockerContainerNameLength = 24;

    private readonly ISessionTargetWorkspaceDiscoveryService workspaceDiscoveryService;
    private readonly ISessionTargetParsingValidationService parsingValidationService;

    public SessionTargetDockerLookupService()
        : this(new SessionTargetWorkspaceDiscoveryService(), new SessionTargetParsingValidationService())
    {
    }

    internal SessionTargetDockerLookupService(
        ISessionTargetWorkspaceDiscoveryService sessionTargetWorkspaceDiscoveryService,
        ISessionTargetParsingValidationService sessionTargetParsingValidationService)
    {
        workspaceDiscoveryService = sessionTargetWorkspaceDiscoveryService ?? throw new ArgumentNullException(nameof(sessionTargetWorkspaceDiscoveryService));
        parsingValidationService = sessionTargetParsingValidationService ?? throw new ArgumentNullException(nameof(sessionTargetParsingValidationService));
    }
}
