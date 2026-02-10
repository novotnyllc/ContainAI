namespace ContainAI.Cli.Host;

internal sealed partial class CaiDiagnosticsStatusCollector
{
    private readonly record struct CaiDiagnosticsContainerTarget(string? Container, string? Context, string? Error);
    private readonly record struct CaiDiagnosticsReportBuildResult(CaiDiagnosticsStatusReport? Report, string? Error);
}
