namespace ContainAI.Cli.Host;

internal interface IImportPathOperations
{
    Task<bool> ResolveImportExcludePrivAsync(string workspace, string? explicitConfigPath, CancellationToken cancellationToken);

    Task<IReadOnlyList<ImportAdditionalPath>> ResolveAdditionalImportPathsAsync(
        string workspace,
        string? explicitConfigPath,
        bool excludePriv,
        string sourceRoot,
        bool verbose,
        CancellationToken cancellationToken);

    Task<int> ImportAdditionalPathAsync(
        string volume,
        ImportAdditionalPath additionalPath,
        bool noExcludes,
        bool dryRun,
        bool verbose,
        CancellationToken cancellationToken);
}

internal sealed partial class CaiImportPathOperations : CaiRuntimeSupport
    , IImportPathOperations
{
    private readonly string importExcludePrivKey;

    public CaiImportPathOperations(TextWriter standardOutput, TextWriter standardError)
        : base(standardOutput, standardError)
        => importExcludePrivKey = "import.exclude_priv";

    public async Task<bool> ResolveImportExcludePrivAsync(string workspace, string? explicitConfigPath, CancellationToken cancellationToken)
    {
        var configPath = ResolveImportConfigPath(workspace, explicitConfigPath);
        if (!File.Exists(configPath))
        {
            return true;
        }

        var result = await RunTomlAsync(
            () => TomlCommandProcessor.GetKey(configPath, importExcludePrivKey),
            cancellationToken).ConfigureAwait(false);
        if (result.ExitCode != 0)
        {
            return true;
        }

        return !bool.TryParse(result.StandardOutput.Trim(), out var parsed) || parsed;
    }

    private static string ResolveImportConfigPath(string workspace, string? explicitConfigPath)
        => !string.IsNullOrWhiteSpace(explicitConfigPath)
            ? explicitConfigPath!
            : ResolveConfigPath(workspace);
}
