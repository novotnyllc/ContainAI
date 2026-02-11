using System.Text.Json;
using ContainAI.Cli.Host.RuntimeSupport.Environment;

namespace ContainAI.Cli.Host.Importing.Environment;

internal interface IImportEnvironmentAllowlistOperations
{
    Task<List<string>> ResolveValidatedImportKeysAsync(JsonElement envSection, bool verbose, CancellationToken cancellationToken);
}

internal sealed class ImportEnvironmentAllowlistOperations : IImportEnvironmentAllowlistOperations
{
    private readonly TextWriter stdout;
    private readonly TextWriter stderr;

    public ImportEnvironmentAllowlistOperations(TextWriter standardOutput, TextWriter standardError)
    {
        stdout = standardOutput ?? throw new ArgumentNullException(nameof(standardOutput));
        stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));
    }

    public async Task<List<string>> ResolveValidatedImportKeysAsync(JsonElement envSection, bool verbose, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        var importKeys = await ResolveImportKeysAsync(envSection).ConfigureAwait(false);
        var dedupedImportKeys = DeduplicateImportKeys(importKeys);

        if (dedupedImportKeys.Count == 0)
        {
            if (verbose)
            {
                await stdout.WriteLineAsync("[INFO] Empty env allowlist, skipping env import").ConfigureAwait(false);
            }

            return [];
        }

        return await ValidateImportKeysAsync(dedupedImportKeys).ConfigureAwait(false);
    }

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

    private static List<string> DeduplicateImportKeys(List<string> importKeys)
    {
        var dedupedImportKeys = new List<string>();
        var seenKeys = new HashSet<string>(StringComparer.Ordinal);
        foreach (var key in importKeys)
        {
            if (seenKeys.Add(key))
            {
                dedupedImportKeys.Add(key);
            }
        }

        return dedupedImportKeys;
    }

    private async Task<List<string>> ValidateImportKeysAsync(List<string> dedupedImportKeys)
    {
        var validatedKeys = new List<string>(dedupedImportKeys.Count);
        foreach (var key in dedupedImportKeys)
        {
            if (!EnvVarNameRegex().IsMatch(key))
            {
                await stderr.WriteLineAsync($"[WARN] Invalid env var name in allowlist: {key}").ConfigureAwait(false);
                continue;
            }

            validatedKeys.Add(key);
        }

        return validatedKeys;
    }

    private static System.Text.RegularExpressions.Regex EnvVarNameRegex()
        => CaiRuntimeEnvRegexHelpers.EnvVarNameRegex();
}
