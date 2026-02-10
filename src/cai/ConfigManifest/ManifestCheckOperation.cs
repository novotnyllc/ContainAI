namespace ContainAI.Cli.Host.ConfigManifest;

internal sealed class ManifestCheckOperation
{
    private readonly TextWriter stdout;
    private readonly TextWriter stderr;
    private readonly IManifestTomlParser manifestTomlParser;
    private readonly IManifestDirectoryResolver manifestDirectoryResolver;
    private readonly ManifestGenerationService generationService;
    private readonly ManifestApplyService applyService;

    public ManifestCheckOperation(
        TextWriter stdout,
        TextWriter stderr,
        IManifestTomlParser manifestTomlParser,
        IManifestDirectoryResolver manifestDirectoryResolver,
        ManifestGenerationService generationService,
        ManifestApplyService applyService)
    {
        this.stdout = stdout ?? throw new ArgumentNullException(nameof(stdout));
        this.stderr = stderr ?? throw new ArgumentNullException(nameof(stderr));
        this.manifestTomlParser = manifestTomlParser ?? throw new ArgumentNullException(nameof(manifestTomlParser));
        this.manifestDirectoryResolver = manifestDirectoryResolver ?? throw new ArgumentNullException(nameof(manifestDirectoryResolver));
        this.generationService = generationService ?? throw new ArgumentNullException(nameof(generationService));
        this.applyService = applyService ?? throw new ArgumentNullException(nameof(applyService));
    }

    internal async Task<int> RunAsync(ManifestCheckRequest request, CancellationToken cancellationToken)
    {
        var manifestDirectory = manifestDirectoryResolver.ResolveManifestDirectory(request.ManifestDirectory);
        if (!Directory.Exists(manifestDirectory))
        {
            await stderr.WriteLineAsync($"ERROR: manifest directory not found: {manifestDirectory}").ConfigureAwait(false);
            return 1;
        }

        var manifestFiles = GetManifestFiles(manifestDirectory);
        if (manifestFiles.Length == 0)
        {
            await stderr.WriteLineAsync($"ERROR: no .toml files found in directory: {manifestDirectory}").ConfigureAwait(false);
            return 1;
        }

        foreach (var file in manifestFiles)
        {
            cancellationToken.ThrowIfCancellationRequested();
            manifestTomlParser.Parse(file, includeDisabled: true, includeSourceFile: false);
        }

        var linkSpec = generationService.GenerateManifest("container-link-spec", manifestDirectory);
        var initApplied = applyService.ApplyInitDirsProbe(manifestDirectory);
        if (initApplied <= 0)
        {
            await stderr.WriteLineAsync("ERROR: init-dir apply produced no operations").ConfigureAwait(false);
            return 1;
        }

        var linkSpecValidationError = ManifestGenerationService.GetLinkSpecValidationError(linkSpec.Content);
        if (linkSpecValidationError is not null)
        {
            await stderr.WriteLineAsync(linkSpecValidationError).ConfigureAwait(false);
            return 1;
        }

        await stdout.WriteLineAsync("Manifest consistency check passed.").ConfigureAwait(false);
        return 0;
    }

    private static string[] GetManifestFiles(string manifestDirectory) =>
        Directory
            .EnumerateFiles(manifestDirectory, "*.toml", SearchOption.TopDirectoryOnly)
            .OrderBy(static path => path, StringComparer.Ordinal)
            .ToArray();
}
