// JSON-RPC 2.0 message types with System.Text.Json source generation for AOT
using System.Diagnostics.CodeAnalysis;
using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;
using System.Text.Json.Serialization.Metadata;

namespace AgentClientProtocol.Proxy.Protocol;

[JsonConverter(typeof(JsonRpcIdConverter))]
public readonly record struct JsonRpcId(string RawValue, bool IsNumeric = false)
{
    public static JsonRpcId FromString(string value) => new(value, false);

    public static JsonRpcId FromNumber(long value) => new(value.ToString(CultureInfo.InvariantCulture), true);

    public static JsonRpcId FromInt32(int value) => FromNumber(value);

    public static JsonRpcId FromInt64(long value) => FromNumber(value);

    public static implicit operator JsonRpcId(string value) => FromString(value);

    public static implicit operator JsonRpcId(int value) => FromInt32(value);

    public static implicit operator JsonRpcId(long value) => FromInt64(value);

    public T? GetValue<T>()
    {
        if (typeof(T) == typeof(string))
        {
            return (T?)(object?)RawValue;
        }

        if (typeof(T) == typeof(int) && int.TryParse(RawValue, NumberStyles.Integer, CultureInfo.InvariantCulture, out var intValue))
        {
            return (T?)(object)intValue;
        }

        if (typeof(T) == typeof(long) && long.TryParse(RawValue, NumberStyles.Integer, CultureInfo.InvariantCulture, out var longValue))
        {
            return (T?)(object)longValue;
        }

        if (typeof(T) == typeof(decimal) && decimal.TryParse(RawValue, NumberStyles.Number, CultureInfo.InvariantCulture, out var decimalValue))
        {
            return (T?)(object)decimalValue;
        }

        if (typeof(T) == typeof(bool) && bool.TryParse(RawValue, out var boolValue))
        {
            return (T?)(object)boolValue;
        }

        throw new NotSupportedException($"JSON-RPC id cannot be converted to {typeof(T).Name}.");
    }

    public override string ToString() => RawValue;
}

internal sealed class JsonRpcIdConverter : JsonConverter<JsonRpcId>
{
    public override JsonRpcId Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options) => reader.TokenType switch
    {
        JsonTokenType.String => JsonRpcId.FromString(reader.GetString() ?? string.Empty),
        JsonTokenType.Number => new JsonRpcId(ReadNumberLiteral(ref reader), IsNumeric: true),
        _ => throw new JsonException("JSON-RPC id must be a string or integer."),
    };

    public override void Write(Utf8JsonWriter writer, JsonRpcId value, JsonSerializerOptions options)
    {
        if (value.IsNumeric)
        {
            try
            {
                writer.WriteRawValue(value.RawValue, skipInputValidation: false);
                return;
            }
            catch (Exception ex) when (ex is JsonException or ArgumentException)
            {
                writer.WriteStringValue(value.RawValue);
                return;
            }
        }

        writer.WriteStringValue(value.RawValue);
    }

    private static string ReadNumberLiteral(ref Utf8JsonReader reader)
    {
        if (reader.HasValueSequence)
        {
            var sequence = reader.ValueSequence;
            var buffer = new byte[checked((int)sequence.Length)];
            var offset = 0;
            foreach (var segment in sequence)
            {
                segment.Span.CopyTo(buffer.AsSpan(offset));
                offset += segment.Length;
            }
            return Encoding.UTF8.GetString(buffer);
        }

        return Encoding.UTF8.GetString(reader.ValueSpan);
    }
}

/// <summary>
/// Strongly typed JSON payload wrapper with object/array traversal helpers.
/// </summary>
[JsonConverter(typeof(JsonRpcDataConverter))]
public readonly record struct JsonRpcData
{
    private readonly JsonElement element;

    public JsonRpcData(JsonElement element) => this.element = element.Clone();

    public JsonElement Element => element;

    public JsonRpcData? this[string propertyName] =>
        element.ValueKind == JsonValueKind.Object && element.TryGetProperty(propertyName, out var propertyValue)
            ? new JsonRpcData(propertyValue)
            : (JsonRpcData?)null;

    public JsonRpcData? this[int index] =>
        element.ValueKind == JsonValueKind.Array &&
        index >= 0 &&
        index < element.GetArrayLength()
            ? new JsonRpcData(element[index])
            : (JsonRpcData?)null;

    public T? GetValue<T>()
    {
        if (typeof(T) == typeof(string) && element.ValueKind == JsonValueKind.String)
        {
            return (T?)(object?)element.GetString();
        }

        if (typeof(T) == typeof(int) && element.ValueKind == JsonValueKind.Number && element.TryGetInt32(out var intValue))
        {
            return (T?)(object)intValue;
        }

        if (typeof(T) == typeof(long) && element.ValueKind == JsonValueKind.Number && element.TryGetInt64(out var longValue))
        {
            return (T?)(object)longValue;
        }

        if (typeof(T) == typeof(decimal) && element.ValueKind == JsonValueKind.Number && element.TryGetDecimal(out var decimalValue))
        {
            return (T?)(object)decimalValue;
        }

        if (typeof(T) == typeof(bool) &&
            (element.ValueKind == JsonValueKind.True || element.ValueKind == JsonValueKind.False))
        {
            return (T?)(object)element.GetBoolean();
        }

        throw new NotSupportedException($"JSON payload cannot be converted to {typeof(T).Name}.");
    }

    public bool TryGetValue<T>(out T value)
    {
        try
        {
            value = GetValue<T>()!;
            return true;
        }
        catch (Exception ex) when (ex is JsonException or NotSupportedException)
        {
            value = default!;
            return false;
        }
    }

    public static implicit operator JsonRpcData(JsonElement element) => new(element);

    public static JsonRpcData FromJsonElement(JsonElement element) => new(element);

    public static implicit operator JsonElement(JsonRpcData payload) => payload.element;

    public static JsonElement ToJsonElement(JsonRpcData payload) => payload.element;

    public static JsonRpcData FromJsonNode(JsonNode node)
    {
        ArgumentNullException.ThrowIfNull(node);
        using var document = JsonDocument.Parse(node.ToJsonString());
        return new JsonRpcData(document.RootElement.Clone());
    }

    public static implicit operator JsonRpcData(JsonNode node) => FromJsonNode(node);

}

internal sealed class JsonRpcDataConverter : JsonConverter<JsonRpcData>
{
    public override JsonRpcData Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        using var document = JsonDocument.ParseValue(ref reader);
        return new JsonRpcData(document.RootElement.Clone());
    }

    public override void Write(Utf8JsonWriter writer, JsonRpcData value, JsonSerializerOptions options)
        => value.Element.WriteTo(writer);
}

/// <summary>
/// JSON-RPC 2.0 envelope (request, response, or notification).
/// </summary>
public sealed class JsonRpcEnvelope
{
    [JsonPropertyName("jsonrpc")]
    public string JsonRpc { get; set; } = "2.0";

    /// <summary>
    /// Request/response ID. Null for notifications.
    /// </summary>
    [JsonPropertyName("id")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public JsonRpcId? Id { get; set; }

    [JsonPropertyName("method")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? Method { get; set; }

    [JsonPropertyName("params")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public JsonRpcData? Params { get; set; }

    [JsonPropertyName("result")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public JsonRpcData? Result { get; set; }

    [JsonPropertyName("error")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public JsonRpcError? Error { get; set; }
}

/// <summary>
/// JSON-RPC 2.0 error object.
/// </summary>
public sealed class JsonRpcError
{
    [JsonPropertyName("code")]
    public int Code { get; set; }

    [JsonPropertyName("message")]
    public string Message { get; set; } = string.Empty;

    [JsonPropertyName("data")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public JsonRpcData? Data { get; set; }
}

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

internal static class AcpExtensionData
{
    public static void MergeInto(IDictionary<string, JsonElement> destination, IReadOnlyDictionary<string, JsonElement>? source)
    {
        ArgumentNullException.ThrowIfNull(destination);

        if (source is null || source.Count == 0)
        {
            return;
        }

        foreach (var (key, value) in source)
        {
            destination[key] = value.Clone();
        }
    }

    public static bool TryGetValue<T>(
        IReadOnlyDictionary<string, JsonElement> extensionData,
        string key,
        JsonTypeInfo<T> typeInfo,
        [NotNullWhen(true)] out T? value)
    {
        ArgumentNullException.ThrowIfNull(extensionData);
        ArgumentException.ThrowIfNullOrWhiteSpace(key);
        ArgumentNullException.ThrowIfNull(typeInfo);

        if (!extensionData.TryGetValue(key, out var element) || element.ValueKind == JsonValueKind.Null)
        {
            value = default;
            return false;
        }

        try
        {
            value = element.Deserialize(typeInfo);
            return value is not null;
        }
        catch (JsonException)
        {
            value = default;
            return false;
        }
    }

    public static void SetValue<T>(
        IDictionary<string, JsonElement> extensionData,
        string key,
        T value,
        JsonTypeInfo<T> typeInfo)
    {
        ArgumentNullException.ThrowIfNull(extensionData);
        ArgumentException.ThrowIfNullOrWhiteSpace(key);
        ArgumentNullException.ThrowIfNull(typeInfo);
        ArgumentNullException.ThrowIfNull(value);

        extensionData[key] = JsonSerializer.SerializeToElement(value, typeInfo);
    }
}

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

/// <summary>
/// Standard JSON-RPC 2.0 error codes.
/// </summary>
public static class JsonRpcErrorCodes
{
    public const int ParseError = -32700;
    public const int InvalidRequest = -32600;
    public const int MethodNotFound = -32601;
    public const int InvalidParams = -32602;
    public const int InternalError = -32603;

    // Server-defined errors (reserved: -32000 to -32099)
    public const int SessionNotFound = -32001;
    public const int SessionCreationFailed = -32000;
}
