namespace ContainAI.Cli.Host;

internal sealed class CaiDiagnosticsStatusOperations : CaiRuntimeSupport
{
    private readonly CaiDiagnosticsStatusCollector statusCollector;
    private readonly CaiDiagnosticsStatusRenderer statusRenderer;

    public CaiDiagnosticsStatusOperations(TextWriter standardOutput, TextWriter standardError)
        : base(standardOutput, standardError)
    {
        var commandDispatcher = new CaiDiagnosticsStatusCommandDispatcher(standardOutput, standardError);
        statusCollector = new CaiDiagnosticsStatusCollector(commandDispatcher);
        statusRenderer = new CaiDiagnosticsStatusRenderer(standardOutput, EscapeJson);
    }

    public async Task<int> RunStatusAsync(
        bool outputJson,
        bool verbose,
        string? workspace,
        string? container,
        CancellationToken cancellationToken)
    {
        var statusRequest = new CaiDiagnosticsStatusRequest(
            workspace,
            container,
            Path.GetFullPath(ExpandHomePath(workspace ?? Directory.GetCurrentDirectory())));

        var collectionResult = await statusCollector.CollectAsync(statusRequest, cancellationToken).ConfigureAwait(false);
        if (!collectionResult.IsSuccess)
        {
            await stderr.WriteLineAsync(collectionResult.ErrorMessage).ConfigureAwait(false);
            return 1;
        }

        await statusRenderer.RenderAsync(collectionResult.Report!, outputJson, verbose).ConfigureAwait(false);
        return 0;
    }
}
