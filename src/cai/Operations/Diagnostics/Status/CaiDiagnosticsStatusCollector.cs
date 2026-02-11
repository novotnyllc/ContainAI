namespace ContainAI.Cli.Host;

internal sealed class CaiDiagnosticsStatusCollector
{
    private readonly CaiDiagnosticsContainerTargetResolver containerTargetResolver;

    public CaiDiagnosticsStatusCollector(CaiDiagnosticsStatusCommandDispatcher commandDispatcher)
    {
        ArgumentNullException.ThrowIfNull(commandDispatcher);

        containerTargetResolver = new CaiDiagnosticsContainerTargetResolver(commandDispatcher);
    }

    public async Task<CaiDiagnosticsStatusCollectionResult> CollectAsync(
        CaiDiagnosticsStatusRequest request,
        CancellationToken cancellationToken)
    {
        var target = await containerTargetResolver.ResolveAsync(request, cancellationToken).ConfigureAwait(false);
        if (!target.IsSuccess)
        {
            return CaiDiagnosticsStatusCollectionResult.Failure(target.ErrorMessage!);
        }

        var reportResult = await CaiDiagnosticsReportBuilder
            .BuildAsync(target.Container!, target.Context!, cancellationToken)
            .ConfigureAwait(false);

        return reportResult.IsSuccess
            ? CaiDiagnosticsStatusCollectionResult.Success(reportResult.Report!)
            : CaiDiagnosticsStatusCollectionResult.Failure(reportResult.ErrorMessage!);
    }
}
