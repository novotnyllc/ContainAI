using CsToml;

namespace ContainAI.Cli.Host;

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
