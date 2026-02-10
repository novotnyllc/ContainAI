namespace ContainAI.Cli.Host;

internal sealed partial class CaiDiagnosticsStatusCollector
{
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
}
