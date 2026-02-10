namespace ContainAI.Cli.Host.ConfigManifest;

internal sealed class ManifestApplyOperation
{
    private readonly TextWriter stderr;
    private readonly ManifestApplyService applyService;

    public ManifestApplyOperation(TextWriter stderr, ManifestApplyService applyService)
    {
        this.stderr = stderr ?? throw new ArgumentNullException(nameof(stderr));
        this.applyService = applyService ?? throw new ArgumentNullException(nameof(applyService));
    }

    internal Task<int> RunAsync(ManifestApplyRequest request, CancellationToken cancellationToken)
        => ManifestCommandErrorHandling.HandleAsync(stderr, async () =>
        {
            cancellationToken.ThrowIfCancellationRequested();
            var applied = applyService.ApplyManifest(
                request.Kind,
                request.ManifestPath,
                request.DataDir,
                request.HomeDir,
                request.ShimDir,
                request.CaiBinaryPath);
            await stderr.WriteLineAsync($"Applied {request.Kind}: {applied}").ConfigureAwait(false);
            return 0;
        });
}
