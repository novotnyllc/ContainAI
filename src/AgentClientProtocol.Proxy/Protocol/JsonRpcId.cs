using System.Globalization;
using System.Text.Json.Serialization;

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
