using System.Text.Json;
using System.Text.Json.Serialization.Metadata;
using AgentClientProtocol.Proxy.Protocol;

namespace AgentClientProtocol.Proxy;

public sealed partial class AcpProxy
{
    private static T? DeserializeElement<T>(JsonRpcData? payload, JsonTypeInfo<T> typeInfo)
    {
        if (payload is null || payload.Value.Element.ValueKind == JsonValueKind.Null)
        {
            return default;
        }

        return payload.Value.Element.Deserialize(typeInfo);
    }

    private static JsonRpcData SerializeElement<T>(T value, JsonTypeInfo<T> typeInfo)
        => JsonSerializer.SerializeToElement(value, typeInfo);

    private static void MergeExtensionData(Dictionary<string, JsonElement> destination, Dictionary<string, JsonElement>? source)
        => AcpExtensionData.MergeInto(destination, source);

    private static void CopySessionNewExtensions(JsonRpcData? result, Dictionary<string, JsonElement> destination)
    {
        ArgumentNullException.ThrowIfNull(destination);

        if (result is not { } payload || payload.Element.ValueKind != JsonValueKind.Object)
        {
            return;
        }

        foreach (var property in payload.Element.EnumerateObject())
        {
            if (string.Equals(property.Name, "sessionId", StringComparison.Ordinal))
            {
                continue;
            }

            destination[property.Name] = property.Value.Clone();
        }
    }
}
