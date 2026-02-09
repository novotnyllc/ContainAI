using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace AgentClientProtocol.Proxy.Protocol;

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
