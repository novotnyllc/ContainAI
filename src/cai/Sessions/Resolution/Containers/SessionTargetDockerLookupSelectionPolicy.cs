using ContainAI.Cli.Host.Sessions.Infrastructure;
using ContainAI.Cli.Host.Sessions.Models;

namespace ContainAI.Cli.Host.Sessions.Resolution.Containers;

internal static class SessionTargetDockerLookupSelectionPolicy
{
    internal const int MaxContainerNameCollisionAttempts = 99;
    private const int MaxDockerContainerNameLength = 24;

    internal static FindContainerByNameResult SelectContainerContextCandidate(string containerName, List<string> foundContexts)
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

    internal static LabelQueryCandidateSelection SelectLabelQueryCandidate(string workspace, string standardOutput)
    {
        var ids = SessionTargetDockerLookupParsing.ParseDockerOutputLines(standardOutput);
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

    internal static string CreateCollisionCandidateName(string baseName, int suffix)
    {
        var suffixText = $"-{suffix + 1}";
        var maxBaseLength = Math.Max(1, MaxDockerContainerNameLength - suffixText.Length);
        var trimmedBase = SessionRuntimeTextHelpers.TrimTrailingDash(baseName[..Math.Min(baseName.Length, maxBaseLength)]);
        return trimmedBase + suffixText;
    }
}

internal readonly record struct LabelQueryCandidateSelection(
    bool ContinueSearch,
    string? ContainerId,
    ContainerLookupResult Result);
