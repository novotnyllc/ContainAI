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
