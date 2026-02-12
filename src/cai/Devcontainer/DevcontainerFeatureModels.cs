using System.Text.Json;
using System.Text.Json.Serialization;

namespace ContainAI.Cli.Host.Devcontainer;

[JsonSerializable(typeof(FeatureConfig))]
[JsonSerializable(typeof(LinkSpecDocument))]
internal partial class DevcontainerFeatureJsonContext : JsonSerializerContext;

internal sealed record FeatureConfig(
    [property: JsonPropertyName("data_volume")] string DataVolume,
    [property: JsonPropertyName("enable_credentials")] bool EnableCredentials,
    [property: JsonPropertyName("enable_ssh")] bool EnableSsh,
    [property: JsonPropertyName("install_docker")] bool InstallDocker,
    [property: JsonPropertyName("remote_user")] string RemoteUser);

internal sealed record LinkSpecDocument(
    [property: JsonPropertyName("home_dir")] string? HomeDirectory,
    [property: JsonPropertyName("links")] IReadOnlyList<LinkEntry>? Links);

internal sealed record LinkEntry(
    [property: JsonPropertyName("link")] string Link,
    [property: JsonPropertyName("target")] string Target,
    [property: JsonPropertyName("remove_first")] bool? RemoveFirst);
