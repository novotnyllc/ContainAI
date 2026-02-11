namespace ContainAI.Cli.Host;

internal sealed partial class SessionContainerProvisioner
{
    private readonly ISessionContainerAttachmentService attachmentService;
    private readonly ISessionContainerLifecycleService lifecycleService;
    private readonly ISessionSshBootstrapService sshBootstrapService;

    public SessionContainerProvisioner(TextWriter standardError)
        : this(standardError, new SessionTargetResolver())
    {
    }

    internal SessionContainerProvisioner(TextWriter standardError, ISessionTargetResolver sessionTargetResolver)
        : this(
            standardError,
            sessionTargetResolver,
            new SessionContainerLifecycleService(standardError, new SessionSshPortAllocator()),
            new SessionSshBootstrapService())
    {
    }

    internal SessionContainerProvisioner(
        TextWriter standardError,
        ISessionTargetResolver sessionTargetResolver,
        ISessionContainerLifecycleService sessionContainerLifecycleService,
        ISessionSshBootstrapService sessionSshBootstrapService)
        : this(
            standardError,
            sessionTargetResolver,
            new SessionContainerAttachmentService(sessionTargetResolver, sessionContainerLifecycleService),
            sessionContainerLifecycleService,
            sessionSshBootstrapService)
    {
    }

    internal SessionContainerProvisioner(
        TextWriter standardError,
        ISessionTargetResolver sessionTargetResolver,
        ISessionContainerAttachmentService sessionContainerAttachmentService,
        ISessionContainerLifecycleService sessionContainerLifecycleService,
        ISessionSshBootstrapService sessionSshBootstrapService)
    {
        ArgumentNullException.ThrowIfNull(standardError);
        ArgumentNullException.ThrowIfNull(sessionTargetResolver);
        ArgumentNullException.ThrowIfNull(sessionContainerAttachmentService);
        ArgumentNullException.ThrowIfNull(sessionContainerLifecycleService);
        ArgumentNullException.ThrowIfNull(sessionSshBootstrapService);

        attachmentService = sessionContainerAttachmentService;
        lifecycleService = sessionContainerLifecycleService;
        sshBootstrapService = sessionSshBootstrapService;
    }
}
