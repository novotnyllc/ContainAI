using CsToml;

namespace ContainAI.Cli.Host;

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
