using System.Text.Json;

namespace ContainAI.Cli.Host.Importing.Environment;

internal sealed partial class ImportEnvironmentAllowlistOperations
{
    private async Task<List<string>> ResolveImportKeysAsync(JsonElement envSection)
    {
        var importKeys = new List<string>();
        if (!envSection.TryGetProperty("import", out var importArray))
        {
            await stderr.WriteLineAsync("[WARN] [env].import missing, treating as empty list").ConfigureAwait(false);
            return importKeys;
        }

        if (importArray.ValueKind != JsonValueKind.Array)
        {
            await stderr.WriteLineAsync($"[WARN] [env].import must be a list, got {importArray.ValueKind}; treating as empty list").ConfigureAwait(false);
            return importKeys;
        }

        var itemIndex = 0;
        foreach (var value in importArray.EnumerateArray())
        {
            if (value.ValueKind == JsonValueKind.String)
            {
                var key = value.GetString();
                if (!string.IsNullOrWhiteSpace(key))
                {
                    importKeys.Add(key);
                }
            }
            else
            {
                await stderr.WriteLineAsync($"[WARN] [env].import[{itemIndex}] must be a string, got {value.ValueKind}; skipping").ConfigureAwait(false);
            }

            itemIndex++;
        }

        return importKeys;
    }
}
