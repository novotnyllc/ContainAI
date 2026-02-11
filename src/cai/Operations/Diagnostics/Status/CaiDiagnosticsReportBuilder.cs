namespace ContainAI.Cli.Host;

internal static class CaiDiagnosticsReportBuilder
{
    public static async Task<CaiDiagnosticsReportBuildResult> BuildAsync(
        string container,
        string context,
        CancellationToken cancellationToken)
    {
        var inspectResult = await CaiDiagnosticsStatusCommandDispatcher
            .InspectContainerStatusAsync(context, container, cancellationToken)
            .ConfigureAwait(false);

        if (inspectResult.ExitCode != 0)
        {
            return CaiDiagnosticsReportBuildResult.Failure($"Failed to inspect container: {container}");
        }

        var inspectParts = inspectResult.StandardOutput.Trim().Split('|');
        if (inspectParts.Length < 3)
        {
            return CaiDiagnosticsReportBuildResult.Failure("Unable to parse container status");
        }

        var status = inspectParts[0];
        var image = inspectParts[1];
        var startedAt = inspectParts[2];
        var uptime = CaiDiagnosticsUptimeFormatter.Format(status, startedAt);
        var resourceUsage = await CaiDiagnosticsResourceUsageCollector
            .CollectAsync(status, context, container, cancellationToken)
            .ConfigureAwait(false);

        var report = new CaiDiagnosticsStatusReport(
            container,
            status,
            image,
            context,
            uptime,
            resourceUsage.MemoryUsage,
            resourceUsage.MemoryLimit,
            resourceUsage.CpuPercent);

        return CaiDiagnosticsReportBuildResult.Success(report);
    }
}

internal readonly record struct CaiDiagnosticsResourceUsage(
    string? MemoryUsage,
    string? MemoryLimit,
    string? CpuPercent)
{
    public static CaiDiagnosticsResourceUsage Empty => new(null, null, null);
}

internal readonly record struct CaiDiagnosticsReportBuildResult(
    bool IsSuccess,
    CaiDiagnosticsStatusReport? Report,
    string? ErrorMessage)
{
    public static CaiDiagnosticsReportBuildResult Success(CaiDiagnosticsStatusReport report)
        => new(true, report, null);

    public static CaiDiagnosticsReportBuildResult Failure(string errorMessage)
        => new(false, null, errorMessage);
}
