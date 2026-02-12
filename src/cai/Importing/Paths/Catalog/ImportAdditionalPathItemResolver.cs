namespace ContainAI.Cli.Host.Importing.Paths;

internal sealed class ImportAdditionalPathItemResolver : IImportAdditionalPathItemResolver
{
    private readonly TextWriter standardError;

    public ImportAdditionalPathItemResolver(TextWriter standardError)
        => this.standardError = standardError ?? throw new ArgumentNullException(nameof(standardError));

    public async Task<IReadOnlyList<ImportAdditionalPath>> ResolveAsync(
        IReadOnlyList<string> rawPaths,
        string sourceRoot,
        bool excludePriv)
    {
        ArgumentNullException.ThrowIfNull(rawPaths);
        ArgumentException.ThrowIfNullOrWhiteSpace(sourceRoot);

        var values = new List<ImportAdditionalPath>();
        var seenSources = new HashSet<string>(StringComparer.Ordinal);

        foreach (var rawPath in rawPaths)
        {
            if (!ImportAdditionalPathResolver.TryResolveAdditionalImportPath(
                    rawPath,
                    sourceRoot,
                    excludePriv,
                    out var resolved,
                    out var warning))
            {
                if (!string.IsNullOrWhiteSpace(warning))
                {
                    await standardError.WriteLineAsync(warning).ConfigureAwait(false);
                }

                continue;
            }

            if (seenSources.Add(resolved.SourcePath))
            {
                values.Add(resolved);
            }
        }

        return values;
    }
}
