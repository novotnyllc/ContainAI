namespace ContainAI.Cli.Host;

internal sealed class CaiDiagnosticsContainerTargetResolver
{
    private readonly CaiDiagnosticsStatusCommandDispatcher commandDispatcher;

    public CaiDiagnosticsContainerTargetResolver(CaiDiagnosticsStatusCommandDispatcher caiDiagnosticsStatusCommandDispatcher)
        => commandDispatcher = caiDiagnosticsStatusCommandDispatcher ?? throw new ArgumentNullException(nameof(caiDiagnosticsStatusCommandDispatcher));

    public async Task<CaiDiagnosticsContainerTargetResolutionResult> ResolveAsync(
        CaiDiagnosticsStatusRequest request,
        CancellationToken cancellationToken)
    {
        if (!string.IsNullOrWhiteSpace(request.Workspace) && !string.IsNullOrWhiteSpace(request.Container))
        {
            return CaiDiagnosticsContainerTargetResolutionResult.Failure("--workspace and --container are mutually exclusive");
        }

        var container = request.Container;
        if (string.IsNullOrWhiteSpace(container))
        {
            container = await commandDispatcher.ResolveContainerForWorkspaceAsync(request.EffectiveWorkspace, cancellationToken).ConfigureAwait(false);
            if (string.IsNullOrWhiteSpace(container))
            {
                return CaiDiagnosticsContainerTargetResolutionResult.Failure(
                    $"No container found for workspace: {request.EffectiveWorkspace}");
            }
        }

        var discoveredContexts = await CaiDiagnosticsStatusCommandDispatcher.DiscoverContainerContextsAsync(container, cancellationToken).ConfigureAwait(false);
        if (discoveredContexts.Count == 0)
        {
            return CaiDiagnosticsContainerTargetResolutionResult.Failure($"Container not found: {container}");
        }

        if (discoveredContexts.Count > 1)
        {
            return CaiDiagnosticsContainerTargetResolutionResult.Failure(
                $"Container '{container}' exists in multiple contexts: {string.Join(", ", discoveredContexts)}");
        }

        var context = discoveredContexts[0];
        var managedResult = await CaiDiagnosticsStatusCommandDispatcher
            .InspectManagedLabelAsync(context, container, cancellationToken)
            .ConfigureAwait(false);

        if (managedResult.ExitCode != 0)
        {
            return CaiDiagnosticsContainerTargetResolutionResult.Failure($"Failed to inspect container: {container}");
        }

        if (!string.Equals(managedResult.StandardOutput.Trim(), "true", StringComparison.Ordinal))
        {
            return CaiDiagnosticsContainerTargetResolutionResult.Failure(
                $"Container {container} exists but is not managed by ContainAI");
        }

        return CaiDiagnosticsContainerTargetResolutionResult.Success(container, context);
    }
}

internal readonly record struct CaiDiagnosticsContainerTargetResolutionResult(
    bool IsSuccess,
    string? Container,
    string? Context,
    string? ErrorMessage)
{
    public static CaiDiagnosticsContainerTargetResolutionResult Success(string container, string context)
        => new(true, container, context, null);

    public static CaiDiagnosticsContainerTargetResolutionResult Failure(string errorMessage)
        => new(false, null, null, errorMessage);
}
