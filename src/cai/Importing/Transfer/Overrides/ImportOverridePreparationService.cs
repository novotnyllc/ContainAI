using ContainAI.Cli.Host.RuntimeSupport.Paths;

namespace ContainAI.Cli.Host.Importing.Transfer;

internal sealed class ImportOverridePreparationService
{
    private readonly TextWriter stderr;

    public ImportOverridePreparationService(TextWriter standardError)
        => stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));

    public async Task<ImportPreparedOverride?> PrepareAsync(
        string overridesDirectory,
        string file,
        IReadOnlyList<ManifestEntry> manifestEntries,
        bool noSecrets,
        bool verbose)
    {
        if (CaiRuntimePathHelpers.IsSymbolicLinkPath(file))
        {
            await stderr.WriteLineAsync($"Skipping override symlink: {file}").ConfigureAwait(false);
            return null;
        }

        var relative = NormalizeOverrideRelativePath(overridesDirectory, file);
        if (!CaiRuntimePathHelpers.TryMapSourcePathToTarget(relative, manifestEntries, out var mappedTarget, out var mappedFlags))
        {
            if (verbose)
            {
                await stderr.WriteLineAsync($"Skipping unmapped override path: {relative}").ConfigureAwait(false);
            }

            return null;
        }

        if (ShouldSkipOverrideForNoSecrets(mappedFlags, noSecrets))
        {
            if (verbose)
            {
                await stderr.WriteLineAsync($"Skipping secret override due to --no-secrets: {relative}").ConfigureAwait(false);
            }

            return null;
        }

        return new ImportPreparedOverride(relative, mappedTarget);
    }

    private static string NormalizeOverrideRelativePath(string overridesDirectory, string file)
    {
        var relative = Path.GetRelativePath(overridesDirectory, file).Replace("\\", "/", StringComparison.Ordinal);
        if (!relative.StartsWith('.'))
        {
            relative = "." + relative;
        }

        return relative;
    }

    private static bool ShouldSkipOverrideForNoSecrets(string mappedFlags, bool noSecrets)
        => noSecrets && mappedFlags.Contains('s', StringComparison.Ordinal);
}
