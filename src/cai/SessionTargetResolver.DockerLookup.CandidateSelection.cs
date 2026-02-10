namespace ContainAI.Cli.Host;

internal sealed partial class SessionTargetDockerLookupService
{
    private static FindContainerByNameResult SelectContainerContextCandidate(string containerName, List<string> foundContexts)
    {
        if (foundContexts.Count == 0)
        {
            return new FindContainerByNameResult(false, null, null, 1);
        }

        if (foundContexts.Count > 1)
        {
            return new FindContainerByNameResult(
                false,
                null,
                $"Container '{containerName}' exists in multiple contexts: {string.Join(", ", foundContexts)}",
                1);
        }

        return new FindContainerByNameResult(true, foundContexts[0], null, 1);
    }

    private static async Task<(bool ContinueSearch, ContainerLookupResult Result)> TryResolveWorkspaceContainerByLabelAsync(
        string workspace,
        string context,
        CancellationToken cancellationToken)
    {
        var byLabel = await QueryContainersByWorkspaceLabelAsync(workspace, context, cancellationToken).ConfigureAwait(false);
        if (byLabel.ExitCode != 0)
        {
            return (false, ContainerLookupResult.Empty());
        }

        var selection = SelectLabelQueryCandidate(workspace, byLabel.StandardOutput);
        if (!selection.ContinueSearch || string.IsNullOrWhiteSpace(selection.ContainerId))
        {
            return (selection.ContinueSearch, selection.Result);
        }

        var nameResult = await QueryContainerNameByIdAsync(context, selection.ContainerId, cancellationToken).ConfigureAwait(false);
        if (nameResult.ExitCode == 0)
        {
            return (false, ContainerLookupResult.Success(ParseContainerName(nameResult.StandardOutput)));
        }

        return (true, ContainerLookupResult.Empty());
    }

    private static LabelQueryCandidateSelection SelectLabelQueryCandidate(string workspace, string standardOutput)
    {
        var ids = ParseDockerOutputLines(standardOutput);
        return ids.Length switch
        {
            0 => new LabelQueryCandidateSelection(true, null, ContainerLookupResult.Empty()),
            1 => new LabelQueryCandidateSelection(true, ids[0], ContainerLookupResult.Empty()),
            _ => new LabelQueryCandidateSelection(
                false,
                null,
                ContainerLookupResult.FromError($"Multiple containers found for workspace: {workspace}")),
        };
    }

    private readonly record struct LabelQueryCandidateSelection(
        bool ContinueSearch,
        string? ContainerId,
        ContainerLookupResult Result);
}
