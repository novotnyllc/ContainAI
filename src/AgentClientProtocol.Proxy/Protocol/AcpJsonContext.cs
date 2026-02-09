using System.Diagnostics.CodeAnalysis;
using System.Text.Json.Serialization;

namespace AgentClientProtocol.Proxy.Protocol;

/// <summary>
/// JSON source generator context for AOT compatibility.
/// </summary>
[JsonSourceGenerationOptions(
    PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase,
    DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull)]
[JsonSerializable(typeof(JsonRpcId))]
[JsonSerializable(typeof(JsonRpcData))]
[JsonSerializable(typeof(JsonRpcEnvelope))]
[JsonSerializable(typeof(JsonRpcError))]
[JsonSerializable(typeof(InitializeRequestParams))]
[JsonSerializable(typeof(InitializeResultPayload))]
[JsonSerializable(typeof(ProxyCapabilities))]
[JsonSerializable(typeof(ProxyServerInfo))]
[JsonSerializable(typeof(SessionNewRequestParams))]
[JsonSerializable(typeof(SessionNewResponsePayload))]
[JsonSerializable(typeof(SessionScopedParams))]
[ExcludeFromCodeCoverage]
public sealed partial class AcpJsonContext : JsonSerializerContext;
