namespace ContainAI.Cli.Host.ConfigManifest;

internal sealed class ManifestGenerateOperation
{
    private readonly TextWriter stdout;
    private readonly TextWriter stderr;
    private readonly ManifestGenerationService generationService;

    public ManifestGenerateOperation(TextWriter stdout, TextWriter stderr, ManifestGenerationService generationService)
    {
        this.stdout = stdout ?? throw new ArgumentNullException(nameof(stdout));
        this.stderr = stderr ?? throw new ArgumentNullException(nameof(stderr));
        this.generationService = generationService ?? throw new ArgumentNullException(nameof(generationService));
    }

    internal Task<int> RunAsync(ManifestGenerateRequest request, CancellationToken cancellationToken)
        => ManifestCommandErrorHandling.HandleAsync(stderr, async () =>
        {
            var generated = generationService.GenerateManifest(request.Kind, request.ManifestPath);
            if (!string.IsNullOrWhiteSpace(request.OutputPath))
            {
                ManifestGenerationService.EnsureOutputDirectory(request.OutputPath);
                await File.WriteAllTextAsync(request.OutputPath, generated.Content, cancellationToken).ConfigureAwait(false);
                await stderr.WriteLineAsync($"Generated: {request.OutputPath} ({generated.Count} links)").ConfigureAwait(false);
                return 0;
            }

            await stdout.WriteAsync(generated.Content).ConfigureAwait(false);
            return 0;
        });
}
