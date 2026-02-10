namespace ContainAI.Cli.Host;

internal sealed partial class CaiDiagnosticsStatusCollector
{
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
