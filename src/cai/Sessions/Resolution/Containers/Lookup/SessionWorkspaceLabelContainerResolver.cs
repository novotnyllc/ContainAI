using ContainAI.Cli.Host.Sessions.Models;
using ContainAI.Cli.Host.Sessions.Resolution.Containers;

namespace ContainAI.Cli.Host.Sessions.Resolution.Containers.Lookup;

internal interface ISessionWorkspaceLabelContainerResolver
{
    Task<LabelContainerLookupResolution> ResolveAsync(string workspace, string context, CancellationToken cancellationToken);
}

internal sealed class SessionWorkspaceLabelContainerResolver(
    ISessionDockerQueryRunner dockerQueryRunner) : ISessionWorkspaceLabelContainerResolver
{
    public async Task<LabelContainerLookupResolution> ResolveAsync(string workspace, string context, CancellationToken cancellationToken)
    {
        var byLabel = await dockerQueryRunner.QueryContainersByWorkspaceLabelAsync(workspace, context, cancellationToken).ConfigureAwait(false);
        if (byLabel.ExitCode != 0)
        {
            return new LabelContainerLookupResolution(false, ContainerLookupResult.Empty());
        }

        var selection = SessionTargetDockerLookupSelectionPolicy.SelectLabelQueryCandidate(workspace, byLabel.StandardOutput);
        if (!selection.ContinueSearch || string.IsNullOrWhiteSpace(selection.ContainerId))
        {
            return new LabelContainerLookupResolution(selection.ContinueSearch, selection.Result);
        }

        var nameResult = await dockerQueryRunner.QueryContainerNameByIdAsync(context, selection.ContainerId, cancellationToken).ConfigureAwait(false);
        if (nameResult.ExitCode == 0)
        {
            return new LabelContainerLookupResolution(
                false,
                ContainerLookupResult.Success(SessionTargetDockerLookupParsing.ParseContainerName(nameResult.StandardOutput)));
        }

        return new LabelContainerLookupResolution(true, ContainerLookupResult.Empty());
    }
}

internal readonly record struct LabelContainerLookupResolution(bool ContinueSearch, ContainerLookupResult Result);
