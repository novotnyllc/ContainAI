using CsToml;

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
            var document = ParseManifestFile(manifestFile);
            if (document is null)
            {
                continue;
            }

            AddSectionEntries(document.E, "entry", manifestFile, includeDisabled, includeSourceFile, entries);
            AddSectionEntries(document.S, "symlink", manifestFile, includeDisabled, includeSourceFile, entries);
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
            var document = ParseManifestFile(manifestFile);
            if (document?.A is null)
            {
                continue;
            }

            var name = ReadString(document.A.N);
            var binary = ReadString(document.A.B);
            var defaultArgs = ReadStringArray(document.A.D);
            var aliases = ReadStringArray(document.A.L);
            var optional = document.A.O;

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
        var bytes = File.ReadAllBytes(manifestFile);
        return CsTomlSerializer.Deserialize<ManifestTomlDocument?>(bytes);
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
            var source = ReadString(item.S);
            var target = ReadString(item.T);
            var containerLink = ReadString(item.C);
            var flags = ReadString(item.F);
            var disabled = item.D;

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

[TomlSerializedObject]
internal sealed partial class ManifestTomlDocument
{
    [TomlValueOnSerialized(AliasName = "entries")]
    public ManifestTomlEntry[]? E { get; set; }

    [TomlValueOnSerialized(AliasName = "container_symlinks")]
    public ManifestTomlEntry[]? S { get; set; }

    [TomlValueOnSerialized(AliasName = "agent")]
    public ManifestTomlAgent? A { get; set; }
}

[TomlSerializedObject]
internal sealed partial class ManifestTomlEntry
{
    [TomlValueOnSerialized(AliasName = "source")]
    public string? S { get; set; }

    [TomlValueOnSerialized(AliasName = "target")]
    public string? T { get; set; }

    [TomlValueOnSerialized(AliasName = "container_link")]
    public string? C { get; set; }

    [TomlValueOnSerialized(AliasName = "flags")]
    public string? F { get; set; }

    [TomlValueOnSerialized(AliasName = "disabled")]
    public bool D { get; set; }
}

[TomlSerializedObject]
internal sealed partial class ManifestTomlAgent
{
    [TomlValueOnSerialized(AliasName = "name")]
    public string? N { get; set; }

    [TomlValueOnSerialized(AliasName = "binary")]
    public string? B { get; set; }

    [TomlValueOnSerialized(AliasName = "default_args")]
    public string[]? D { get; set; }

    [TomlValueOnSerialized(AliasName = "aliases")]
    public string[]? L { get; set; }

    [TomlValueOnSerialized(AliasName = "optional")]
    public bool O { get; set; }
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
