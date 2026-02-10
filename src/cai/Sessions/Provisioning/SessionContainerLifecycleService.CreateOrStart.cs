namespace ContainAI.Cli.Host;

internal sealed partial class SessionContainerLifecycleService
{
    public async Task<ResolutionResult<string>> CreateOrStartContainerAsync(
        SessionCommandOptions options,
        ResolvedTarget resolved,
        ExistingContainerAttachment attachment,
        CancellationToken cancellationToken)
    {
        if (!attachment.Exists)
        {
            var created = await createStartOrchestrator.CreateContainerAsync(options, resolved, cancellationToken).ConfigureAwait(false);
            if (!created.Success)
            {
                return ResolutionResult<string>.ErrorResult(created.Error!, created.ErrorCode);
            }

            return ResolutionResult<string>.SuccessResult(created.Value!.SshPort);
        }

        var sshPort = attachment.SshPort ?? string.Empty;
        if (string.IsNullOrWhiteSpace(sshPort))
        {
            var allocated = await sshPortAllocator.AllocateSshPortAsync(resolved.Context, cancellationToken).ConfigureAwait(false);
            if (!allocated.Success)
            {
                return allocated;
            }

            sshPort = allocated.Value!;
        }

        if (!string.Equals(attachment.State, "running", StringComparison.Ordinal))
        {
            var start = await createStartOrchestrator.StartContainerAsync(
                resolved.Context,
                resolved.ContainerName,
                cancellationToken).ConfigureAwait(false);
            if (!start.Success)
            {
                return ResolutionResult<string>.ErrorResult(start.Error!, start.ErrorCode);
            }
        }

        return ResolutionResult<string>.SuccessResult(sshPort);
    }
}
