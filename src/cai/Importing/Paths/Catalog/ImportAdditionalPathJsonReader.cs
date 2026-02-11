using System.Text.Json;

namespace ContainAI.Cli.Host.Importing.Paths;

internal interface IImportAdditionalPathJsonReader
{
    Task<IReadOnlyList<string>> ReadRawAdditionalPathsAsync(
        string configJson,
        bool verbose);
}

internal sealed class ImportAdditionalPathJsonReader : IImportAdditionalPathJsonReader
{
    private readonly TextWriter standardError;

    public ImportAdditionalPathJsonReader(TextWriter standardError)
        => this.standardError = standardError ?? throw new ArgumentNullException(nameof(standardError));

    public async Task<IReadOnlyList<string>> ReadRawAdditionalPathsAsync(
        string configJson,
        bool verbose)
    {
        try
        {
            using var document = JsonDocument.Parse(configJson);
            if (!TryGetAdditionalPathsElement(document.RootElement, out var pathsElement))
            {
                return [];
            }

            if (pathsElement.ValueKind != JsonValueKind.Array)
            {
                await standardError.WriteLineAsync("[WARN] [import].additional_paths must be a list; ignoring").ConfigureAwait(false);
                return [];
            }

            return await ReadRawPathItemsAsync(pathsElement).ConfigureAwait(false);
        }
        catch (JsonException ex)
        {
            if (verbose)
            {
                await standardError.WriteLineAsync($"[WARN] Failed to parse config JSON for additional paths: {ex.Message}").ConfigureAwait(false);
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

    private async Task<IReadOnlyList<string>> ReadRawPathItemsAsync(JsonElement pathsElement)
    {
        var values = new List<string>();

        foreach (var item in pathsElement.EnumerateArray())
        {
            if (item.ValueKind != JsonValueKind.String)
            {
                await standardError.WriteLineAsync($"[WARN] [import].additional_paths item must be a string; got {item.ValueKind}").ConfigureAwait(false);
                continue;
            }

            var rawPath = item.GetString();
            if (!string.IsNullOrWhiteSpace(rawPath))
            {
                values.Add(rawPath);
            }
        }

        return values;
    }
}
