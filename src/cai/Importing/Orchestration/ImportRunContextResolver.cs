using ContainAI.Cli.Abstractions;
using ContainAI.Cli.Host.RuntimeSupport.Paths;

namespace ContainAI.Cli.Host;

internal sealed record ImportRunContext(
    string Workspace,
    string? ExplicitConfigPath,
    string Volume,
    string SourcePath,
    bool ExcludePriv);

internal interface IImportRunContextResolver
{
    Task<ResolutionResult<ImportRunContext>> ResolveAsync(ImportCommandOptions options, CancellationToken cancellationToken);
}

internal sealed class ImportRunContextResolver : IImportRunContextResolver
{
    private static readonly string[] ConfigFileNames =
    [
        "config.toml",
        "containai.toml",
    ];

    private readonly IImportPathOperations pathOperations;

    public ImportRunContextResolver(
        TextWriter standardOutput,
        TextWriter standardError,
        IImportPathOperations importPathOperations)
    {
        ArgumentNullException.ThrowIfNull(standardOutput);
        ArgumentNullException.ThrowIfNull(standardError);
        pathOperations = importPathOperations ?? throw new ArgumentNullException(nameof(importPathOperations));
    }

    public async Task<ResolutionResult<ImportRunContext>> ResolveAsync(ImportCommandOptions options, CancellationToken cancellationToken)
    {
        var workspace = string.IsNullOrWhiteSpace(options.Workspace)
            ? Directory.GetCurrentDirectory()
            : Path.GetFullPath(CaiRuntimeHomePathHelpers.ExpandHomePath(options.Workspace));
        var explicitConfigPath = string.IsNullOrWhiteSpace(options.Config)
            ? null
            : Path.GetFullPath(CaiRuntimeHomePathHelpers.ExpandHomePath(options.Config));

        if (!string.IsNullOrWhiteSpace(explicitConfigPath) && !File.Exists(explicitConfigPath))
        {
            return ResolutionResult<ImportRunContext>.ErrorResult($"Config file not found: {explicitConfigPath}");
        }

        var volume = await CaiRuntimePathResolutionHelpers
            .ResolveDataVolumeAsync(workspace, options.DataVolume, ConfigFileNames, cancellationToken)
            .ConfigureAwait(false);
        if (string.IsNullOrWhiteSpace(volume))
        {
            return ResolutionResult<ImportRunContext>.ErrorResult("Unable to resolve data volume. Use --data-volume.");
        }

        var sourcePath = string.IsNullOrWhiteSpace(options.From)
            ? CaiRuntimeHomePathHelpers.ResolveHomeDirectory()
            : Path.GetFullPath(CaiRuntimeHomePathHelpers.ExpandHomePath(options.From));
        if (!File.Exists(sourcePath) && !Directory.Exists(sourcePath))
        {
            return ResolutionResult<ImportRunContext>.ErrorResult($"Import source not found: {sourcePath}");
        }

        var excludePriv = await pathOperations.ResolveImportExcludePrivAsync(workspace, explicitConfigPath, cancellationToken).ConfigureAwait(false);
        return ResolutionResult<ImportRunContext>.SuccessResult(
            new ImportRunContext(workspace, explicitConfigPath, volume, sourcePath, excludePriv));
    }
}
