namespace ContainAI.Cli.Host;

internal static class CaiDiagnosticsResourceUsageCollector
{
    public static async Task<CaiDiagnosticsResourceUsage> CollectAsync(
        string status,
        string context,
        string container,
        CancellationToken cancellationToken)
    {
        if (!string.Equals(status, "running", StringComparison.Ordinal))
        {
            return CaiDiagnosticsResourceUsage.Empty;
        }

        var statsResult = await CaiDiagnosticsStatusCommandDispatcher
            .InspectContainerStatsAsync(context, container, cancellationToken)
            .ConfigureAwait(false);

        if (statsResult.ExitCode != 0)
        {
            return CaiDiagnosticsResourceUsage.Empty;
        }

        var statsParts = statsResult.StandardOutput.Trim().Split('|');
        if (statsParts.Length < 2)
        {
            return CaiDiagnosticsResourceUsage.Empty;
        }

        var cpuPercent = statsParts[1];
        var memoryParts = statsParts[0].Split(" / ", StringSplitOptions.TrimEntries);
        if (memoryParts.Length != 2)
        {
            return new CaiDiagnosticsResourceUsage(null, null, cpuPercent);
        }

        return new CaiDiagnosticsResourceUsage(memoryParts[0], memoryParts[1], cpuPercent);
    }
}
