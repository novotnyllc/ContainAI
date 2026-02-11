namespace ContainAI.Cli.Host;

internal sealed class SessionContainerProvisioner
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

    public async Task<EnsuredSession> EnsureAsync(
        SessionCommandOptions options,
        ResolvedTarget resolved,
        CancellationToken cancellationToken)
    {
        var attachment = await attachmentService.FindAttachableContainerAsync(options, resolved, cancellationToken).ConfigureAwait(false);
        if (!attachment.Success)
        {
            return EnsureError(attachment);
        }

        var runningContainer = await lifecycleService.CreateOrStartContainerAsync(
            options,
            resolved,
            attachment.Value!,
            cancellationToken).ConfigureAwait(false);
        if (!runningContainer.Success)
        {
            return EnsureError(runningContainer);
        }

        var sshPort = runningContainer.Value!;

        var sshBootstrap = await sshBootstrapService.EnsureSshBootstrapAsync(resolved, sshPort, cancellationToken).ConfigureAwait(false);
        if (!sshBootstrap.Success)
        {
            return EnsureError(sshBootstrap);
        }

        return new EnsuredSession(
            ContainerName: resolved.ContainerName,
            Workspace: resolved.Workspace,
            DataVolume: resolved.DataVolume,
            Context: resolved.Context,
            SshPort: sshPort,
            Error: null,
            ErrorCode: 1);
    }

    private static EnsuredSession EnsureError<T>(ResolutionResult<T> result) =>
        EnsuredSession.ErrorResult(result.Error!, result.ErrorCode);
}
