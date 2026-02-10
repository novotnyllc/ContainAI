namespace ContainAI.Cli.Host.Importing.Environment;

internal sealed partial class ImportEnvironmentAllowlistOperations
{
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
}
