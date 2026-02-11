namespace ContainAI.Cli.Host;

internal static class CaiDiagnosticsUptimeFormatter
{
    public static string? Format(string status, string startedAt)
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
