namespace ContainAI.Cli.Host;

internal sealed partial class SessionContainerProvisioner
{
    private readonly TextWriter stderr;
    private readonly ISessionTargetResolver targetResolver;

    public SessionContainerProvisioner(TextWriter standardError)
        : this(standardError, new SessionTargetResolver())
    {
    }

    internal SessionContainerProvisioner(TextWriter standardError, ISessionTargetResolver sessionTargetResolver)
    {
        ArgumentNullException.ThrowIfNull(standardError);
        ArgumentNullException.ThrowIfNull(sessionTargetResolver);

        stderr = standardError;
        targetResolver = sessionTargetResolver;
    }

    public async Task<EnsuredSession> EnsureAsync(
        SessionCommandOptions options,
        ResolvedTarget resolved,
        CancellationToken cancellationToken)
    {
        var attachment = await FindAttachableContainerAsync(options, resolved, cancellationToken).ConfigureAwait(false);
        if (!attachment.Success)
        {
            return EnsureError(attachment);
        }

        var runningContainer = await CreateOrStartContainerAsync(options, resolved, attachment.Value!, cancellationToken).ConfigureAwait(false);
        if (!runningContainer.Success)
        {
            return EnsureError(runningContainer);
        }

        var sshPort = runningContainer.Value!;

        var sshBootstrap = await EnsureSshBootstrapAsync(resolved, sshPort, cancellationToken).ConfigureAwait(false);
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
}
