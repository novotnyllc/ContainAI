namespace ContainAI.Cli.Host;

internal sealed partial class CaiDiagnosticsStatusCollector
{
    private readonly record struct CaiDiagnosticsContainerTarget(string? Container, string? Context, string? Error);
    private readonly record struct CaiDiagnosticsReportBuildResult(CaiDiagnosticsStatusReport? Report, string? Error);

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

    private static async Task<CaiDiagnosticsReportBuildResult> BuildReportAsync(
        string container,
        string context,
        CancellationToken cancellationToken)
    {
        var inspectResult = await CaiDiagnosticsStatusCommandDispatcher.InspectContainerStatusAsync(context, container, cancellationToken).ConfigureAwait(false);
        if (inspectResult.ExitCode != 0)
        {
            return new CaiDiagnosticsReportBuildResult(null, $"Failed to inspect container: {container}");
        }

        var inspectParts = inspectResult.StandardOutput.Trim().Split('|');
        if (inspectParts.Length < 3)
        {
            return new CaiDiagnosticsReportBuildResult(null, "Unable to parse container status");
        }

        var status = inspectParts[0];
        var image = inspectParts[1];
        var startedAt = inspectParts[2];
        var uptime = CalculateUptime(status, startedAt);
        var resourceUsage = await CollectResourceUsageAsync(status, context, container, cancellationToken).ConfigureAwait(false);

        return new CaiDiagnosticsReportBuildResult(
            new CaiDiagnosticsStatusReport(
                container,
                status,
                image,
                context,
                uptime,
                resourceUsage.MemoryUsage,
                resourceUsage.MemoryLimit,
                resourceUsage.CpuPercent),
            null);
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
