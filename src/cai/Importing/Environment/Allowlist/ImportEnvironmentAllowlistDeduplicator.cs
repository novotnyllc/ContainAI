namespace ContainAI.Cli.Host.Importing.Environment;

internal static class ImportEnvironmentAllowlistDeduplicator
{
    public static List<string> Deduplicate(List<string> importKeys)
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
}
