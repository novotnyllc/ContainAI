using ContainAI.Cli.Host.Sessions.Models;
using ContainAI.Cli.Host.Sessions.Resolution.Containers;
using ContainAI.Cli.Host.Sessions.Resolution.Orchestration;

namespace ContainAI.Cli.Host.Sessions.Resolution.Orchestration.ExplicitContainer;

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
