using CsToml;

namespace ContainAI.Cli.Host;

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
