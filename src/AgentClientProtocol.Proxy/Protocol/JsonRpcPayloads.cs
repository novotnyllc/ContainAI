using System.Text.Json;
using System.Text.Json.Serialization;

namespace AgentClientProtocol.Proxy.Protocol;

public sealed class InitializeRequestParams
{
    [JsonPropertyName("protocolVersion")]
    public string? ProtocolVersion { get; set; }

    [JsonPropertyName("clientInfo")]
    public JsonRpcData? ClientInfo { get; set; }

    [JsonPropertyName("capabilities")]
    public JsonRpcData? Capabilities { get; set; }

    [JsonExtensionData]
    public Dictionary<string, JsonElement> ExtensionData { get; } = new(StringComparer.Ordinal);
}

public sealed class InitializeResultPayload
{
    [JsonPropertyName("protocolVersion")]
    public string ProtocolVersion { get; set; } = "2025-01-01";

    [JsonPropertyName("capabilities")]
    public ProxyCapabilities Capabilities { get; set; } = new();

    [JsonPropertyName("serverInfo")]
    public ProxyServerInfo ServerInfo { get; set; } = new();
}

public sealed class ProxyCapabilities
{
    [JsonPropertyName("multiSession")]
    public bool MultiSession { get; set; } = true;
}

public sealed class ProxyServerInfo
{
    [JsonPropertyName("name")]
    public string Name { get; set; } = "containai-acp-proxy";

    [JsonPropertyName("version")]
    public string Version { get; set; } = "0.1.0";
}

public sealed class SessionNewRequestParams
{
    [JsonPropertyName("cwd")]
    public string? Cwd { get; set; }

    [JsonPropertyName("mcpServers")]
    public JsonRpcData? McpServers { get; set; }

    [JsonExtensionData]
    public Dictionary<string, JsonElement> ExtensionData { get; } = new(StringComparer.Ordinal);
}

public sealed class SessionNewResponsePayload
{
    [JsonPropertyName("sessionId")]
    public string? SessionId { get; set; }

    [JsonExtensionData]
    public Dictionary<string, JsonElement> ExtensionData { get; } = new(StringComparer.Ordinal);
}

public sealed class SessionScopedParams
{
    [JsonPropertyName("sessionId")]
    public string? SessionId { get; set; }

    [JsonExtensionData]
    public Dictionary<string, JsonElement> ExtensionData { get; } = new(StringComparer.Ordinal);
}
