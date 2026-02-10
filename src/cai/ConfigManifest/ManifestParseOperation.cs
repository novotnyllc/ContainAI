namespace ContainAI.Cli.Host.ConfigManifest;

internal sealed class ManifestParseOperation
{
    private readonly TextWriter stdout;
    private readonly TextWriter stderr;
    private readonly IManifestTomlParser manifestTomlParser;

    public ManifestParseOperation(TextWriter stdout, TextWriter stderr, IManifestTomlParser manifestTomlParser)
    {
        this.stdout = stdout ?? throw new ArgumentNullException(nameof(stdout));
        this.stderr = stderr ?? throw new ArgumentNullException(nameof(stderr));
        this.manifestTomlParser = manifestTomlParser ?? throw new ArgumentNullException(nameof(manifestTomlParser));
    }

    internal Task<int> RunAsync(ManifestParseRequest request, CancellationToken cancellationToken)
        => ManifestCommandErrorHandling.HandleAsync(stderr, async () =>
        {
            var parsed = manifestTomlParser.Parse(request.ManifestPath, request.IncludeDisabled, request.EmitSourceFile);
            foreach (var entry in parsed)
            {
                cancellationToken.ThrowIfCancellationRequested();
                await stdout.WriteLineAsync(entry.ToString()).ConfigureAwait(false);
            }

            return 0;
        });
}
