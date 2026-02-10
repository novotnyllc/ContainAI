using ContainAI.Cli.Host.Manifests.Apply;

namespace ContainAI.Cli.Host.ConfigManifest;

internal sealed class ManifestCommandProcessor : IManifestCommandProcessor
{
    private readonly ManifestParseOperation parseOperation;
    private readonly ManifestGenerateOperation generateOperation;
    private readonly ManifestApplyOperation applyOperation;
    private readonly ManifestCheckOperation checkOperation;

    public ManifestCommandProcessor(
        TextWriter standardOutput,
        TextWriter standardError,
        IManifestTomlParser manifestTomlParser,
        IManifestApplier manifestApplier,
        IManifestDirectoryResolver manifestDirectoryResolver)
    {
        ArgumentNullException.ThrowIfNull(standardOutput);
        ArgumentNullException.ThrowIfNull(standardError);
        ArgumentNullException.ThrowIfNull(manifestTomlParser);
        ArgumentNullException.ThrowIfNull(manifestApplier);
        ArgumentNullException.ThrowIfNull(manifestDirectoryResolver);

        var generationService = new ManifestGenerationService(manifestTomlParser);
        var applyService = new ManifestApplyService(manifestApplier);
        parseOperation = new ManifestParseOperation(standardOutput, standardError, manifestTomlParser);
        generateOperation = new ManifestGenerateOperation(standardOutput, standardError, generationService);
        applyOperation = new ManifestApplyOperation(standardError, applyService);
        checkOperation = new ManifestCheckOperation(standardOutput, standardError, manifestTomlParser, manifestDirectoryResolver, generationService, applyService);
    }

    public Task<int> RunParseAsync(ManifestParseRequest request, CancellationToken cancellationToken)
        => parseOperation.RunAsync(request, cancellationToken);

    public Task<int> RunGenerateAsync(ManifestGenerateRequest request, CancellationToken cancellationToken)
        => generateOperation.RunAsync(request, cancellationToken);

    public Task<int> RunApplyAsync(ManifestApplyRequest request, CancellationToken cancellationToken)
        => applyOperation.RunAsync(request, cancellationToken);

    public Task<int> RunCheckAsync(ManifestCheckRequest request, CancellationToken cancellationToken)
        => checkOperation.RunAsync(request, cancellationToken);
}
