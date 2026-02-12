namespace ContainAI.Cli.Host.Importing.Paths;

internal interface IImportAdditionalPathItemResolver
{
    Task<IReadOnlyList<ImportAdditionalPath>> ResolveAsync(
        IReadOnlyList<string> rawPaths,
        string sourceRoot,
        bool excludePriv);
}
