namespace ContainAI.Cli.Host;

internal readonly record struct CaiDiagnosticsStatusRequest(
    string? Workspace,
    string? Container,
    string EffectiveWorkspace);

internal sealed record CaiDiagnosticsStatusReport(
    string Container,
    string Status,
    string Image,
    string Context,
    string? Uptime,
    string? MemoryUsage,
    string? MemoryLimit,
    string? CpuPercent);

internal readonly record struct CaiDiagnosticsStatusCollectionResult(
    bool IsSuccess,
    CaiDiagnosticsStatusReport? Report,
    string? ErrorMessage)
{
    public static CaiDiagnosticsStatusCollectionResult Success(CaiDiagnosticsStatusReport report)
        => new(true, report, null);

    public static CaiDiagnosticsStatusCollectionResult Failure(string errorMessage)
        => new(false, null, errorMessage);
}

internal readonly record struct CaiDiagnosticsStatusCommandResult(
    int ExitCode,
    string StandardOutput,
    string StandardError);
