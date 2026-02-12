using ContainAI.Cli.Host.Sessions.Models;
using ContainAI.Cli.Host.Sessions.Resolution.Orchestration;

namespace ContainAI.Cli.Host.Sessions.Provisioning;

internal interface ISessionContainerAttachmentService
{
    Task<ResolutionResult<ExistingContainerAttachment>> FindAttachableContainerAsync(
        SessionCommandOptions options,
        ResolvedTarget resolved,
        CancellationToken cancellationToken);
}
