using ContainAI.Cli.Host.Sessions.Models;

namespace ContainAI.Cli.Host.Sessions.Resolution.Orchestration;

internal interface ISessionTargetExplicitContainerTargetFactory
{
    ResolutionResult<ResolvedTarget> CreateFromExistingContainer(
        SessionCommandOptions options,
        string containerName,
        string context,
        ContainerLabelState labels);
}
