using ContainAI.Cli.Host.Sessions.Models;
using ContainAI.Cli.Host.Sessions.Resolution.Orchestration;

namespace ContainAI.Cli.Host.Sessions.Provisioning;

internal sealed class SessionContainerAttachmentService : ISessionContainerAttachmentService
{
    private readonly ISessionTargetResolver targetResolver;
    private readonly ISessionContainerLifecycleService lifecycleService;

    public SessionContainerAttachmentService()
        : this(new SessionTargetResolver(), new SessionContainerLifecycleService())
    {
    }

    internal SessionContainerAttachmentService(
        ISessionTargetResolver sessionTargetResolver,
        ISessionContainerLifecycleService sessionContainerLifecycleService)
    {
        targetResolver = sessionTargetResolver ?? throw new ArgumentNullException(nameof(sessionTargetResolver));
        lifecycleService = sessionContainerLifecycleService ?? throw new ArgumentNullException(nameof(sessionContainerLifecycleService));
    }

    public async Task<ResolutionResult<ExistingContainerAttachment>> FindAttachableContainerAsync(
        SessionCommandOptions options,
        ResolvedTarget resolved,
        CancellationToken cancellationToken)
    {
        var labelState = await targetResolver.ReadContainerLabelsAsync(
            resolved.ContainerName,
            resolved.Context,
            cancellationToken).ConfigureAwait(false);
        var exists = labelState.Exists;

        if (exists && !labelState.IsOwned)
        {
            var code = options.Mode == SessionMode.Run ? 1 : 15;
            return ResolutionResult<ExistingContainerAttachment>.ErrorResult(
                $"Container '{resolved.ContainerName}' exists but was not created by ContainAI",
                code);
        }

        if (options.Fresh && exists)
        {
            await lifecycleService.RemoveContainerAsync(resolved.Context, resolved.ContainerName, cancellationToken).ConfigureAwait(false);
            exists = false;
        }

        if (exists &&
            !string.IsNullOrWhiteSpace(options.DataVolume) &&
            !string.Equals(labelState.DataVolume, resolved.DataVolume, StringComparison.Ordinal))
        {
            return ResolutionResult<ExistingContainerAttachment>.ErrorResult(
                $"Container '{resolved.ContainerName}' already uses volume '{labelState.DataVolume}'. Use --fresh to recreate with a different volume.");
        }

        if (!exists)
        {
            return ResolutionResult<ExistingContainerAttachment>.SuccessResult(ExistingContainerAttachment.NotFound);
        }

        return ResolutionResult<ExistingContainerAttachment>.SuccessResult(
            new ExistingContainerAttachment(
                Exists: true,
                State: labelState.State,
                SshPort: labelState.SshPort));
    }
}
