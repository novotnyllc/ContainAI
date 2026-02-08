using System.Globalization;
using Tomlyn;
using Tomlyn.Model;

namespace ContainAI.Cli.Host;

internal static class ManifestTomlParser
{
    public static IReadOnlyList<ManifestEntry> Parse(
        string manifestPath,
        bool includeDisabled,
        bool includeSourceFile)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(manifestPath);

        var manifestFiles = ResolveManifestFiles(manifestPath);
        var entries = new List<ManifestEntry>();
        foreach (var manifestFile in manifestFiles)
        {
            var content = File.ReadAllText(manifestFile);
            var model = Toml.ToModel(content);
            if (model is not TomlTable root)
            {
                continue;
            }

            AddSectionEntries(root, "entries", "entry", manifestFile, includeDisabled, includeSourceFile, entries);
            AddSectionEntries(root, "container_symlinks", "symlink", manifestFile, includeDisabled, includeSourceFile, entries);
        }

        return entries;
    }

    public static IReadOnlyList<ManifestAgentEntry> ParseAgents(string manifestPath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(manifestPath);

        var manifestFiles = ResolveManifestFiles(manifestPath);
        var entries = new List<ManifestAgentEntry>();
        foreach (var manifestFile in manifestFiles)
        {
            var content = File.ReadAllText(manifestFile);
            var model = Toml.ToModel(content);
            if (model is not TomlTable root)
            {
                continue;
            }

            if (!root.TryGetValue("agent", out var sectionValue) || sectionValue is not TomlTable section)
            {
                continue;
            }

            var name = ReadString(section, "name");
            var binary = ReadString(section, "binary");
            var defaultArgs = ReadStringArray(section, "default_args");
            var aliases = ReadStringArray(section, "aliases");
            var optional = ReadBool(section, "optional");

            if (string.IsNullOrWhiteSpace(name) || string.IsNullOrWhiteSpace(binary) || defaultArgs.Count == 0)
            {
                continue;
            }

            entries.Add(new ManifestAgentEntry(
                Name: name,
                Binary: binary,
                DefaultArgs: defaultArgs,
                Aliases: aliases,
                Optional: optional,
                SourceFile: manifestFile));
        }

        return entries;
    }

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

    private static void AddSectionEntries(
        TomlTable root,
        string sectionName,
        string entryType,
        string manifestFile,
        bool includeDisabled,
        bool includeSourceFile,
        List<ManifestEntry> entries)
    {
        if (!root.TryGetValue(sectionName, out var sectionValue) || sectionValue is not TomlTableArray sectionArray)
        {
            return;
        }

        foreach (var item in sectionArray)
        {
            if (item is not TomlTable table)
            {
                continue;
            }

            var source = ReadString(table, "source");
            var target = ReadString(table, "target");
            var containerLink = ReadString(table, "container_link");
            var flags = ReadString(table, "flags");
            var disabled = ReadBool(table, "disabled");

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

    private static string ReadString(TomlTable table, string key)
    {
        if (!table.TryGetValue(key, out var value) || value is null)
        {
            return string.Empty;
        }

        return value switch
        {
            string text => text,
            _ => Convert.ToString(value, CultureInfo.InvariantCulture) ?? string.Empty,
        };
    }

    private static bool ReadBool(TomlTable table, string key)
    {
        if (!table.TryGetValue(key, out var value) || value is null)
        {
            return false;
        }

        if (value is bool booleanValue)
        {
            return booleanValue;
        }

        if (value is string text && bool.TryParse(text, out var parsed))
        {
            return parsed;
        }

        return false;
    }

    private static List<string> ReadStringArray(TomlTable table, string key)
    {
        if (!table.TryGetValue(key, out var value) || value is not TomlArray array)
        {
            return [];
        }

        var values = new List<string>(array.Count);
        foreach (var item in array)
        {
            if (item is string text && !string.IsNullOrWhiteSpace(text))
            {
                values.Add(text);
            }
        }

        return values;
    }
}

internal readonly record struct ManifestEntry(
    string Source,
    string Target,
    string ContainerLink,
    string Flags,
    bool Disabled,
    string Type,
    bool Optional,
    string? SourceFile)
{
    public override string ToString()
    {
        var disabled = Disabled ? "true" : "false";
        var optional = Optional ? "true" : "false";

        return SourceFile is null
            ? $"{Source}|{Target}|{ContainerLink}|{Flags}|{disabled}|{Type}|{optional}"
            : $"{Source}|{Target}|{ContainerLink}|{Flags}|{disabled}|{Type}|{optional}|{SourceFile}";
    }
}

internal readonly record struct ManifestAgentEntry(
    string Name,
    string Binary,
    IReadOnlyList<string> DefaultArgs,
    IReadOnlyList<string> Aliases,
    bool Optional,
    string SourceFile);
