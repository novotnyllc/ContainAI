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
            if (document.RootElement.ValueKind != JsonValueKind.Object ||
                !document.RootElement.TryGetProperty("import", out var importElement) ||
                importElement.ValueKind != JsonValueKind.Object ||
                !importElement.TryGetProperty("additional_paths", out var pathsElement))
            {
                return [];
            }

            if (pathsElement.ValueKind != JsonValueKind.Array)
            {
                await stderr.WriteLineAsync("[WARN] [import].additional_paths must be a list; ignoring").ConfigureAwait(false);
                return [];
            }

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
        catch (JsonException ex)
        {
            if (verbose)
            {
                await stderr.WriteLineAsync($"[WARN] Failed to parse config JSON for additional paths: {ex.Message}").ConfigureAwait(false);
            }

            return [];
        }
    }
}
