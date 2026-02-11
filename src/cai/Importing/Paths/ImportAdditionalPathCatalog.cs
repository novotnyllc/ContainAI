using System.Text.Json;
using ContainAI.Cli.Host;

namespace ContainAI.Cli.Host.Importing.Paths;

internal sealed class ImportAdditionalPathCatalog : CaiRuntimeSupport
    , IImportAdditionalPathCatalog
{
    public ImportAdditionalPathCatalog(TextWriter standardOutput, TextWriter standardError)
        : base(standardOutput, standardError)
    {
    }

    public async Task<IReadOnlyList<ImportAdditionalPath>> ResolveAdditionalImportPathsAsync(
        string configPath,
        bool excludePriv,
        string sourceRoot,
        bool verbose,
        CancellationToken cancellationToken)
    {
        if (!File.Exists(configPath))
        {
            return [];
        }

        var result = await RunTomlAsync(() => TomlCommandProcessor.GetJson(configPath), cancellationToken).ConfigureAwait(false);
        if (result.ExitCode != 0)
        {
            if (verbose && !string.IsNullOrWhiteSpace(result.StandardError))
            {
                await stderr.WriteLineAsync(result.StandardError.Trim()).ConfigureAwait(false);
            }

            return [];
        }

        try
        {
            using var document = JsonDocument.Parse(result.StandardOutput);
            if (!TryGetAdditionalPathsElement(document.RootElement, out var pathsElement))
            {
                return [];
            }

            if (pathsElement.ValueKind != JsonValueKind.Array)
            {
                await stderr.WriteLineAsync("[WARN] [import].additional_paths must be a list; ignoring").ConfigureAwait(false);
                return [];
            }

            return await ResolveAdditionalImportPathsAsync(pathsElement, sourceRoot, excludePriv).ConfigureAwait(false);
        }
        catch (JsonException ex)
        {
            if (verbose)
            {
                await stderr.WriteLineAsync($"[WARN] Failed to parse config JSON for additional paths: {ex.Message}").ConfigureAwait(false);
            }

            return [];
        }
    }

    private static bool TryGetAdditionalPathsElement(JsonElement rootElement, out JsonElement pathsElement)
    {
        if (rootElement.ValueKind != JsonValueKind.Object ||
            !rootElement.TryGetProperty("import", out var importElement) ||
            importElement.ValueKind != JsonValueKind.Object ||
            !importElement.TryGetProperty("additional_paths", out pathsElement))
        {
            pathsElement = default;
            return false;
        }

        return true;
    }

    private async Task<IReadOnlyList<ImportAdditionalPath>> ResolveAdditionalImportPathsAsync(
        JsonElement pathsElement,
        string sourceRoot,
        bool excludePriv)
    {
        var values = new List<ImportAdditionalPath>();
        var seenSources = new HashSet<string>(StringComparer.Ordinal);

        foreach (var item in pathsElement.EnumerateArray())
        {
            if (item.ValueKind != JsonValueKind.String)
            {
                await stderr.WriteLineAsync($"[WARN] [import].additional_paths item must be a string; got {item.ValueKind}").ConfigureAwait(false);
                continue;
            }

            var rawPath = item.GetString();
            if (!ImportAdditionalPathResolver.TryResolveAdditionalImportPath(
                    rawPath,
                    sourceRoot,
                    excludePriv,
                    out var resolved,
                    out var warning))
            {
                if (!string.IsNullOrWhiteSpace(warning))
                {
                    await stderr.WriteLineAsync(warning).ConfigureAwait(false);
                }

                continue;
            }

            if (!seenSources.Add(resolved.SourcePath))
            {
                continue;
            }

            values.Add(resolved);
        }

        return values;
    }
}
