using CsToml;
using CsToml.Error;

namespace ContainAI.Cli.Host;

internal interface IManifestTomlParser
{
    IReadOnlyList<ManifestEntry> Parse(string manifestPath, bool includeDisabled, bool includeSourceFile);

    IReadOnlyList<ManifestAgentEntry> ParseAgents(string manifestPath);
}

internal sealed class ManifestTomlParser : IManifestTomlParser
{
    public IReadOnlyList<ManifestEntry> Parse(
        string manifestPath,
        bool includeDisabled,
        bool includeSourceFile)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(manifestPath);

        var manifestFiles = ResolveManifestFiles(manifestPath);
        var entries = new List<ManifestEntry>();
        foreach (var manifestFile in manifestFiles)
        {
            var document = ParseManifestFile(manifestFile);
            if (document is null)
            {
                continue;
            }

            AddSectionEntries(document.Entries, "entry", manifestFile, includeDisabled, includeSourceFile, entries);
            AddSectionEntries(document.ContainerSymlinks, "symlink", manifestFile, includeDisabled, includeSourceFile, entries);
        }

        return entries;
    }

    public IReadOnlyList<ManifestAgentEntry> ParseAgents(string manifestPath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(manifestPath);

        var manifestFiles = ResolveManifestFiles(manifestPath);
        var entries = new List<ManifestAgentEntry>();
        foreach (var manifestFile in manifestFiles)
        {
            var document = ParseManifestFile(manifestFile);
            if (document?.Agent is null)
            {
                continue;
            }

            var name = ReadString(document.Agent.Name);
            var binary = ReadString(document.Agent.Binary);
            var defaultArgs = ReadStringArray(document.Agent.DefaultArgs);
            var aliases = ReadStringArray(document.Agent.Aliases);
            var optional = document.Agent.Optional;

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

[TomlSerializedObject(NamingConvention = TomlNamingConvention.SnakeCase)]
internal sealed partial class ManifestTomlDocument
{
    [TomlValueOnSerialized]
    public ManifestTomlEntry[]? Entries { get; set; }

    [TomlValueOnSerialized]
    public ManifestTomlEntry[]? ContainerSymlinks { get; set; }

    [TomlValueOnSerialized]
    public ManifestTomlAgent? Agent { get; set; }
}

[TomlSerializedObject(NamingConvention = TomlNamingConvention.SnakeCase)]
internal sealed partial class ManifestTomlEntry
{
    [TomlValueOnSerialized]
    public string? Source { get; set; }

    [TomlValueOnSerialized]
    public string? Target { get; set; }

    [TomlValueOnSerialized]
    public string? ContainerLink { get; set; }

    [TomlValueOnSerialized]
    public string? Flags { get; set; }

    [TomlValueOnSerialized]
    public bool Disabled { get; set; }
}

[TomlSerializedObject(NamingConvention = TomlNamingConvention.SnakeCase)]
internal sealed partial class ManifestTomlAgent
{
    [TomlValueOnSerialized]
    public string? Name { get; set; }

    [TomlValueOnSerialized]
    public string? Binary { get; set; }

    [TomlValueOnSerialized]
    public string[]? DefaultArgs { get; set; }

    [TomlValueOnSerialized]
    public string[]? Aliases { get; set; }

    [TomlValueOnSerialized]
    public bool Optional { get; set; }
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
