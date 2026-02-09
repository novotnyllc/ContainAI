using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;

namespace AgentClientProtocol.Proxy.Protocol;

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
