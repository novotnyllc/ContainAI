namespace ContainAI.Cli.Host;

internal sealed partial class CaiDiagnosticsStatusCollector
{
    private async Task<CaiDiagnosticsContainerTarget> ResolveContainerTargetAsync(
        CaiDiagnosticsStatusRequest request,
        CancellationToken cancellationToken)
    {
        if (!string.IsNullOrWhiteSpace(request.Workspace) && !string.IsNullOrWhiteSpace(request.Container))
        {
            return new CaiDiagnosticsContainerTarget(null, null, "--workspace and --container are mutually exclusive");
        }

        var container = request.Container;
        if (string.IsNullOrWhiteSpace(container))
        {
            container = await commandDispatcher.ResolveContainerForWorkspaceAsync(request.EffectiveWorkspace, cancellationToken).ConfigureAwait(false);
            if (string.IsNullOrWhiteSpace(container))
            {
                return new CaiDiagnosticsContainerTarget(
                    null,
                    null,
                    $"No container found for workspace: {request.EffectiveWorkspace}");
            }
        }

        var discoveredContexts = await CaiDiagnosticsStatusCommandDispatcher.DiscoverContainerContextsAsync(container, cancellationToken).ConfigureAwait(false);
        if (discoveredContexts.Count == 0)
        {
            return new CaiDiagnosticsContainerTarget(null, null, $"Container not found: {container}");
        }

        if (discoveredContexts.Count > 1)
        {
            return new CaiDiagnosticsContainerTarget(
                null,
                null,
                $"Container '{container}' exists in multiple contexts: {string.Join(", ", discoveredContexts)}");
        }

        var context = discoveredContexts[0];
        var managedResult = await CaiDiagnosticsStatusCommandDispatcher.InspectManagedLabelAsync(context, container, cancellationToken).ConfigureAwait(false);
        if (managedResult.ExitCode != 0)
        {
            return new CaiDiagnosticsContainerTarget(null, null, $"Failed to inspect container: {container}");
        }

        if (!string.Equals(managedResult.StandardOutput.Trim(), "true", StringComparison.Ordinal))
        {
            return new CaiDiagnosticsContainerTarget(null, null, $"Container {container} exists but is not managed by ContainAI");
        }

        return new CaiDiagnosticsContainerTarget(container, context, null);
    }
}
