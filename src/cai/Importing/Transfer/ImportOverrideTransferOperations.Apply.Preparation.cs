namespace ContainAI.Cli.Host.Importing.Transfer;

internal sealed partial class ImportOverrideTransferOperations
{
    private readonly record struct PreparedOverride(string RelativePath, string MappedTargetPath);

    private static string[] GetOverrideFiles(string overridesDirectory)
        => Directory.EnumerateFiles(overridesDirectory, "*", SearchOption.AllDirectories)
            .OrderBy(static path => path, StringComparer.Ordinal)
            .ToArray();

    private async Task<PreparedOverride?> PrepareOverrideFileAsync(
        string overridesDirectory,
        string file,
        IReadOnlyList<ManifestEntry> manifestEntries,
        bool noSecrets,
        bool verbose)
    {
        if (IsSymbolicLinkPath(file))
        {
            await stderr.WriteLineAsync($"Skipping override symlink: {file}").ConfigureAwait(false);
            return null;
        }

        var relative = NormalizeOverrideRelativePath(overridesDirectory, file);
        if (!TryMapSourcePathToTarget(relative, manifestEntries, out var mappedTarget, out var mappedFlags))
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

        return new PreparedOverride(relative, mappedTarget);
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
}
