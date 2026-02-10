namespace ContainAI.Cli.Host;

internal sealed partial class CaiDiagnosticsStatusCollector
{
    private readonly CaiDiagnosticsStatusCommandDispatcher commandDispatcher;

    public CaiDiagnosticsStatusCollector(CaiDiagnosticsStatusCommandDispatcher commandDispatcher) => this.commandDispatcher = commandDispatcher;

    public async Task<CaiDiagnosticsStatusCollectionResult> CollectAsync(
        CaiDiagnosticsStatusRequest request,
        CancellationToken cancellationToken)
    {
        var target = await ResolveContainerTargetAsync(request, cancellationToken).ConfigureAwait(false);
        if (!string.IsNullOrWhiteSpace(target.Error))
        {
            return CaiDiagnosticsStatusCollectionResult.Failure(target.Error!);
        }

        var report = await BuildReportAsync(target.Container!, target.Context!, cancellationToken).ConfigureAwait(false);
        if (!string.IsNullOrWhiteSpace(report.Error))
        {
            return CaiDiagnosticsStatusCollectionResult.Failure(report.Error!);
        }

        return CaiDiagnosticsStatusCollectionResult.Success(report.Report!);
    }
}
