namespace ContainAI.Cli.Host;

internal interface ISessionTargetExistingContainerResolver
{
    Task<ResolvedTarget> ResolveAsync(SessionCommandOptions options, string context, CancellationToken cancellationToken);
}

internal sealed class SessionTargetExistingContainerResolver(
    ISessionTargetDockerLookupService dockerLookupService,
    ISessionTargetExplicitContainerTargetFactory explicitContainerTargetFactory) : ISessionTargetExistingContainerResolver
{
    public async Task<ResolvedTarget> ResolveAsync(SessionCommandOptions options, string context, CancellationToken cancellationToken)
    {
        var labels = await dockerLookupService.ReadContainerLabelsAsync(options.Container!, context, cancellationToken).ConfigureAwait(false);
        var existingContainerTarget = explicitContainerTargetFactory.CreateFromExistingContainer(
            options,
            options.Container!,
            context,
            labels);
        if (!existingContainerTarget.Success)
        {
            return ResolvedTarget.ErrorResult(existingContainerTarget.Error!, existingContainerTarget.ErrorCode);
        }

        return existingContainerTarget.Value!;
    }
}
