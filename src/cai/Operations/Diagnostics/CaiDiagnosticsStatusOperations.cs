using ContainAI.Cli.Host.RuntimeSupport.Paths;
using ContainAI.Cli.Host.RuntimeSupport.Process;

namespace ContainAI.Cli.Host;

internal sealed class CaiDiagnosticsStatusOperations
{
    private readonly TextWriter stderr;
    private readonly CaiDiagnosticsStatusCollector statusCollector;
    private readonly CaiDiagnosticsStatusRenderer statusRenderer;

    public CaiDiagnosticsStatusOperations(TextWriter standardOutput, TextWriter standardError)
    {
        stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));
        var commandDispatcher = new CaiDiagnosticsStatusCommandDispatcher(standardOutput, standardError);
        statusCollector = new CaiDiagnosticsStatusCollector(commandDispatcher);
        statusRenderer = new CaiDiagnosticsStatusRenderer(standardOutput, CaiRuntimeJsonEscaper.EscapeJson);
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
            Path.GetFullPath(CaiRuntimeHomePathHelpers.ExpandHomePath(workspace ?? Directory.GetCurrentDirectory())));

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
