using ContainAI.Cli.Host;

namespace ContainAI.Cli.Host.Importing.Paths;

internal sealed class ImportAdditionalPathCatalog : IImportAdditionalPathCatalog
{
    private readonly IImportAdditionalPathConfigReader configReader;
    private readonly IImportAdditionalPathItemResolver itemResolver;

    public ImportAdditionalPathCatalog(TextWriter standardOutput, TextWriter standardError)
        : this(
            standardOutput,
            standardError,
            new ImportAdditionalPathConfigReader(standardError),
            new ImportAdditionalPathItemResolver(standardError))
    {
    }

    internal ImportAdditionalPathCatalog(
        TextWriter standardOutput,
        TextWriter standardError,
        IImportAdditionalPathConfigReader importAdditionalPathConfigReader,
        IImportAdditionalPathItemResolver importAdditionalPathItemResolver)
    {
        ArgumentNullException.ThrowIfNull(standardOutput);
        ArgumentNullException.ThrowIfNull(standardError);
        configReader = importAdditionalPathConfigReader ?? throw new ArgumentNullException(nameof(importAdditionalPathConfigReader));
        itemResolver = importAdditionalPathItemResolver ?? throw new ArgumentNullException(nameof(importAdditionalPathItemResolver));
    }

    public async Task<IReadOnlyList<ImportAdditionalPath>> ResolveAdditionalImportPathsAsync(
        string configPath,
        bool excludePriv,
        string sourceRoot,
        bool verbose,
        CancellationToken cancellationToken)
        => await itemResolver.ResolveAsync(
            await configReader.ReadRawAdditionalPathsAsync(configPath, verbose, cancellationToken).ConfigureAwait(false),
            sourceRoot,
            excludePriv).ConfigureAwait(false);
}
