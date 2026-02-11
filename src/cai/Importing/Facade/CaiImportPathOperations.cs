using ContainAI.Cli.Host.Importing.Paths;
using ContainAI.Cli.Host.RuntimeSupport.Parsing;
using ContainAI.Cli.Host.RuntimeSupport.Paths;

namespace ContainAI.Cli.Host;

internal sealed class CaiImportPathOperations : IImportPathOperations
{
    private static readonly string[] ConfigFileNames =
    [
        "config.toml",
        "containai.toml",
    ];

    private readonly string importExcludePrivKey;
    private readonly IImportAdditionalPathCatalog additionalPathCatalog;
    private readonly IImportAdditionalPathTransferOperations additionalPathTransferOperations;

    public CaiImportPathOperations(TextWriter standardOutput, TextWriter standardError)
        : this(
            standardOutput,
            standardError,
            new ImportAdditionalPathCatalog(standardOutput, standardError),
            new ImportAdditionalPathTransferOperations(standardOutput, standardError))
    {
    }

    internal CaiImportPathOperations(
        TextWriter standardOutput,
        TextWriter standardError,
        IImportAdditionalPathCatalog additionalPathCatalog,
        IImportAdditionalPathTransferOperations additionalPathTransferOperations)
    {
        ArgumentNullException.ThrowIfNull(standardOutput);
        ArgumentNullException.ThrowIfNull(standardError);
        (importExcludePrivKey, this.additionalPathCatalog, this.additionalPathTransferOperations) = (
            "import.exclude_priv",
            additionalPathCatalog ?? throw new ArgumentNullException(nameof(additionalPathCatalog)),
            additionalPathTransferOperations ?? throw new ArgumentNullException(nameof(additionalPathTransferOperations)));
    }

    public async Task<bool> ResolveImportExcludePrivAsync(string workspace, string? explicitConfigPath, CancellationToken cancellationToken)
    {
        var configPath = ResolveImportConfigPath(workspace, explicitConfigPath);
        if (!File.Exists(configPath))
        {
            return true;
        }

        var result = await CaiRuntimeParseAndTimeHelpers.RunTomlAsync(
            () => TomlCommandProcessor.GetKey(configPath, importExcludePrivKey),
            cancellationToken).ConfigureAwait(false);
        if (result.ExitCode != 0)
        {
            return true;
        }

        return !bool.TryParse(result.StandardOutput.Trim(), out var parsed) || parsed;
    }

    public Task<IReadOnlyList<ImportAdditionalPath>> ResolveAdditionalImportPathsAsync(
        string workspace,
        string? explicitConfigPath,
        bool excludePriv,
        string sourceRoot,
        bool verbose,
        CancellationToken cancellationToken)
    {
        var configPath = ResolveImportConfigPath(workspace, explicitConfigPath);
        return additionalPathCatalog.ResolveAdditionalImportPathsAsync(configPath, excludePriv, sourceRoot, verbose, cancellationToken);
    }

    public Task<int> ImportAdditionalPathAsync(
        string volume,
        ImportAdditionalPath additionalPath,
        bool noExcludes,
        bool dryRun,
        bool verbose,
        CancellationToken cancellationToken)
        => additionalPathTransferOperations.ImportAdditionalPathAsync(volume, additionalPath, noExcludes, dryRun, verbose, cancellationToken);

    private static string ResolveImportConfigPath(string workspace, string? explicitConfigPath)
        => !string.IsNullOrWhiteSpace(explicitConfigPath)
            ? explicitConfigPath!
            : CaiRuntimeConfigLocator.ResolveConfigPath(workspace, ConfigFileNames);
}
