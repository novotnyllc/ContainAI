using CsToml;
using CsToml.Error;

namespace ContainAI.Cli.Host;

internal sealed partial class ManifestTomlParser
{
    private static string[] ResolveManifestFiles(string manifestPath)
    {
        if (Directory.Exists(manifestPath))
        {
            var files = Directory
                .EnumerateFiles(manifestPath, "*.toml", SearchOption.TopDirectoryOnly)
                .OrderBy(static file => file, StringComparer.Ordinal)
                .ToArray();

            if (files.Length == 0)
            {
                throw new InvalidOperationException($"no .toml files found in directory: {manifestPath}");
            }

            return files;
        }

        if (File.Exists(manifestPath))
        {
            return [manifestPath];
        }

        throw new InvalidOperationException($"manifest file or directory not found: {manifestPath}");
    }

    private static ManifestTomlDocument? ParseManifestFile(string manifestFile)
    {
        try
        {
            var bytes = File.ReadAllBytes(manifestFile);
            return CsTomlSerializer.Deserialize<ManifestTomlDocument?>(bytes);
        }
        catch (CsTomlException ex)
        {
            throw new InvalidOperationException($"invalid TOML in manifest '{manifestFile}': {ex.Message}", ex);
        }
    }

    private static void AddSectionEntries(
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
            var source = ReadString(item.Source);
            var target = ReadString(item.Target);
            var containerLink = ReadString(item.ContainerLink);
            var flags = ReadString(item.Flags);
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

    private static string ReadString(string? value) => value ?? string.Empty;

    private static List<string> ReadStringArray(string[]? values)
        => values?
            .Where(static value => !string.IsNullOrWhiteSpace(value))
            .ToList()
        ?? [];
}
