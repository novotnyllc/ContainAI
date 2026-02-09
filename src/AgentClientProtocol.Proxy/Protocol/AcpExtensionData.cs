using System.Diagnostics.CodeAnalysis;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.Json.Serialization.Metadata;

namespace AgentClientProtocol.Proxy.Protocol;

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
