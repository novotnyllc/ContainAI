namespace ContainAI.Cli.Host;

internal sealed class CaiDiagnosticsStatusCollector
{
    private readonly CaiDiagnosticsStatusCommandDispatcher commandDispatcher;

    public CaiDiagnosticsStatusCollector(CaiDiagnosticsStatusCommandDispatcher commandDispatcher) => this.commandDispatcher = commandDispatcher;

    public async Task<CaiDiagnosticsStatusCollectionResult> CollectAsync(
        CaiDiagnosticsStatusRequest request,
        CancellationToken cancellationToken)
    {
        if (!string.IsNullOrWhiteSpace(request.Workspace) && !string.IsNullOrWhiteSpace(request.Container))
        {
            return CaiDiagnosticsStatusCollectionResult.Failure("--workspace and --container are mutually exclusive");
        }

        var container = request.Container;
        if (string.IsNullOrWhiteSpace(container))
        {
            container = await commandDispatcher.ResolveContainerForWorkspaceAsync(request.EffectiveWorkspace, cancellationToken).ConfigureAwait(false);
            if (string.IsNullOrWhiteSpace(container))
            {
                return CaiDiagnosticsStatusCollectionResult.Failure($"No container found for workspace: {request.EffectiveWorkspace}");
            }
        }

        var discoveredContexts = await CaiDiagnosticsStatusCommandDispatcher.DiscoverContainerContextsAsync(container, cancellationToken).ConfigureAwait(false);
        if (discoveredContexts.Count == 0)
        {
            return CaiDiagnosticsStatusCollectionResult.Failure($"Container not found: {container}");
        }

        if (discoveredContexts.Count > 1)
        {
            return CaiDiagnosticsStatusCollectionResult.Failure(
                $"Container '{container}' exists in multiple contexts: {string.Join(", ", discoveredContexts)}");
        }

        var context = discoveredContexts[0];

        var managedResult = await CaiDiagnosticsStatusCommandDispatcher.InspectManagedLabelAsync(context, container, cancellationToken).ConfigureAwait(false);
        if (managedResult.ExitCode != 0)
        {
            return CaiDiagnosticsStatusCollectionResult.Failure($"Failed to inspect container: {container}");
        }

        if (!string.Equals(managedResult.StandardOutput.Trim(), "true", StringComparison.Ordinal))
        {
            return CaiDiagnosticsStatusCollectionResult.Failure($"Container {container} exists but is not managed by ContainAI");
        }

        var inspectResult = await CaiDiagnosticsStatusCommandDispatcher.InspectContainerStatusAsync(context, container, cancellationToken).ConfigureAwait(false);
        if (inspectResult.ExitCode != 0)
        {
            return CaiDiagnosticsStatusCollectionResult.Failure($"Failed to inspect container: {container}");
        }

        var inspectParts = inspectResult.StandardOutput.Trim().Split('|');
        if (inspectParts.Length < 3)
        {
            return CaiDiagnosticsStatusCollectionResult.Failure("Unable to parse container status");
        }

        var status = inspectParts[0];
        var image = inspectParts[1];
        var startedAt = inspectParts[2];
        var uptime = CalculateUptime(status, startedAt);

        var resourceUsage = await CollectResourceUsageAsync(status, context, container, cancellationToken).ConfigureAwait(false);

        var report = new CaiDiagnosticsStatusReport(
            container,
            status,
            image,
            context,
            uptime,
            resourceUsage.MemoryUsage,
            resourceUsage.MemoryLimit,
            resourceUsage.CpuPercent);

        return CaiDiagnosticsStatusCollectionResult.Success(report);
    }

    private static async Task<(string? MemoryUsage, string? MemoryLimit, string? CpuPercent)> CollectResourceUsageAsync(
        string status,
        string context,
        string container,
        CancellationToken cancellationToken)
    {
        if (!string.Equals(status, "running", StringComparison.Ordinal))
        {
            return (null, null, null);
        }

        var statsResult = await CaiDiagnosticsStatusCommandDispatcher.InspectContainerStatsAsync(context, container, cancellationToken).ConfigureAwait(false);
        if (statsResult.ExitCode != 0)
        {
            return (null, null, null);
        }

        string? memoryUsage = null;
        string? memoryLimit = null;
        string? cpuPercent = null;

        var statsParts = statsResult.StandardOutput.Trim().Split('|');
        if (statsParts.Length >= 2)
        {
            cpuPercent = statsParts[1];
            var memoryParts = statsParts[0].Split(" / ", StringSplitOptions.TrimEntries);
            if (memoryParts.Length == 2)
            {
                memoryUsage = memoryParts[0];
                memoryLimit = memoryParts[1];
            }
        }

        return (memoryUsage, memoryLimit, cpuPercent);
    }

    private static string? CalculateUptime(string status, string startedAt)
    {
        if (!string.Equals(status, "running", StringComparison.Ordinal) ||
            !DateTimeOffset.TryParse(startedAt, out var started))
        {
            return null;
        }

        var elapsed = DateTimeOffset.UtcNow - started;
        if (elapsed.TotalDays >= 1)
        {
            return $"{(int)elapsed.TotalDays}d {elapsed.Hours}h {elapsed.Minutes}m";
        }

        if (elapsed.TotalHours >= 1)
        {
            return $"{elapsed.Hours}h {elapsed.Minutes}m";
        }

        return $"{Math.Max(0, elapsed.Minutes)}m";
    }
}
