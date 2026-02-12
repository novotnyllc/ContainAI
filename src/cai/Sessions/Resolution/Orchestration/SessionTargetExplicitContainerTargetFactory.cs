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

internal sealed class SessionTargetExplicitContainerTargetFactory : ISessionTargetExplicitContainerTargetFactory
{
    public ResolutionResult<ResolvedTarget> CreateFromExistingContainer(
        SessionCommandOptions options,
        string containerName,
        string context,
        ContainerLabelState labels)
    {
        if (!labels.IsOwned)
        {
            var code = options.Mode == SessionMode.Run ? 1 : 15;
            return ResolutionResult<ResolvedTarget>.ErrorResult($"Container '{containerName}' exists but was not created by ContainAI", code);
        }

        if (string.IsNullOrWhiteSpace(labels.Workspace))
        {
            return ResolutionResult<ResolvedTarget>.ErrorResult($"Container {containerName} is missing workspace label");
        }

        if (string.IsNullOrWhiteSpace(labels.DataVolume))
        {
            return ResolutionResult<ResolvedTarget>.ErrorResult($"Container {containerName} is missing data-volume label");
        }

        return ResolutionResult<ResolvedTarget>.SuccessResult(
            new ResolvedTarget(
                ContainerName: containerName,
                Workspace: labels.Workspace,
                DataVolume: labels.DataVolume,
                Context: context,
                ShouldPersistState: true,
                CreatedByThisInvocation: false,
                GeneratedFromReset: false,
                Error: null,
                ErrorCode: 1));
    }
}
