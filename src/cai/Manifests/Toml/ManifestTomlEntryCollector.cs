namespace ContainAI.Cli.Host;

internal static class ManifestTomlEntryCollector
{
    public static void AddSectionEntries(
        ManifestTomlEntry[]? sectionEntries,
        string entryType,
        string manifestFile,
        bool includeDisabled,
        bool includeSourceFile,
        List<ManifestEntry> entries)
    {
        if (sectionEntries is null)
        {
            return;
        }

        foreach (var item in sectionEntries)
        {
            var source = ManifestTomlValueReader.ReadString(item.Source);
            var target = ManifestTomlValueReader.ReadString(item.Target);
            var containerLink = ManifestTomlValueReader.ReadString(item.ContainerLink);
            var flags = ManifestTomlValueReader.ReadString(item.Flags);
            var disabled = item.Disabled;

            if (string.IsNullOrEmpty(target))
            {
                continue;
            }

            if (disabled && !includeDisabled)
            {
                continue;
            }

            var optional = flags.Contains('o', StringComparison.Ordinal);
            entries.Add(new ManifestEntry(
                source,
                target,
                containerLink,
                flags,
                disabled,
                entryType,
                optional,
                includeSourceFile ? manifestFile : null));
        }
    }
}
