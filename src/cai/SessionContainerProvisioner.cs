namespace ContainAI.Cli.Host;

internal sealed partial class SessionContainerProvisioner
{
    private readonly TextWriter stderr;

    public SessionContainerProvisioner(TextWriter standardError) => stderr = standardError;

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
