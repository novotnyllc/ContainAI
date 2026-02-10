using System.Text.Json;

namespace ContainAI.Cli.Host.Importing.Paths;

internal sealed partial class ImportAdditionalPathCatalog
{
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
