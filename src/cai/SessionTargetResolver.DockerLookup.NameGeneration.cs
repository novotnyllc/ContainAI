namespace ContainAI.Cli.Host;

internal sealed partial class SessionTargetDockerLookupService
{
    private async Task<ResolutionResult<string>> ResolveNameWithCollisionHandlingAsync(
        string workspace,
        string context,
        string baseName,
        CancellationToken cancellationToken)
    {
        var candidate = baseName;
        for (var suffix = 1; suffix <= MaxContainerNameCollisionAttempts; suffix++)
        {
            if (await IsNameAvailableOrOwnedByWorkspaceAsync(candidate, workspace, context, cancellationToken).ConfigureAwait(false))
            {
                return ResolutionResult<string>.SuccessResult(candidate);
            }

            candidate = CreateCollisionCandidateName(baseName, suffix);
        }

        return ResolutionResult<string>.ErrorResult("Too many container name collisions (max 99)");
    }

    private async Task<bool> IsNameAvailableOrOwnedByWorkspaceAsync(
        string candidate,
        string workspace,
        string context,
        CancellationToken cancellationToken)
    {
        var inspect = await QueryContainerInspectAsync(candidate, context, cancellationToken).ConfigureAwait(false);
        if (inspect.ExitCode != 0)
        {
            return true;
        }

        var labels = await ReadContainerLabelsAsync(candidate, context, cancellationToken).ConfigureAwait(false);
        return string.Equals(labels.Workspace, workspace, StringComparison.Ordinal);
    }

    private static string CreateCollisionCandidateName(string baseName, int suffix)
    {
        var suffixText = $"-{suffix + 1}";
        var maxBaseLength = Math.Max(1, MaxDockerContainerNameLength - suffixText.Length);
        var trimmedBase = SessionRuntimeInfrastructure.TrimTrailingDash(baseName[..Math.Min(baseName.Length, maxBaseLength)]);
        return trimmedBase + suffixText;
    }
}
