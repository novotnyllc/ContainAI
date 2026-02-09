using System.Buffers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using AgentClientProtocol.Proxy.Protocol;
using Xunit;

namespace AgentClientProtocol.Proxy.Tests;

public sealed class JsonRpcDataAndIdTests
{
    [Fact]
    public void JsonRpcId_ImplicitAndFactoryConversions_Work()
    {
        JsonRpcId stringId = "req-1";
        JsonRpcId intId = 42;
        JsonRpcId longId = 9876543210L;
        var explicitNumericStringId = JsonRpcId.FromString("12.5");

        Assert.Equal("req-1", stringId.RawValue);
        Assert.False(stringId.IsNumeric);
        Assert.Equal("42", intId.RawValue);
        Assert.True(intId.IsNumeric);
        Assert.Equal("9876543210", longId.RawValue);
        Assert.True(longId.IsNumeric);
        Assert.Equal("12.5", explicitNumericStringId.RawValue);
    }

    [Fact]
    public void JsonRpcId_GetValue_ReturnsTypedValue_AndThrowsForUnsupported()
    {
        var numericId = (JsonRpcId)123;
        var boolId = JsonRpcId.FromString("true");

        Assert.Equal(123, numericId.GetValue<int>());
        Assert.Equal(123L, numericId.GetValue<long>());
        Assert.Equal(123m, numericId.GetValue<decimal>());
        Assert.True(boolId.GetValue<bool>());
        Assert.Throws<NotSupportedException>(() => numericId.GetValue<DateTime>());
    }

    [Fact]
    public void JsonRpcId_GetValue_WithInvalidNumericOrBoolean_ThrowsNotSupported()
    {
        var nonNumeric = JsonRpcId.FromString("alpha");
        var nonBoolean = JsonRpcId.FromString("not-bool");

        Assert.Throws<NotSupportedException>(() => nonNumeric.GetValue<int>());
        Assert.Throws<NotSupportedException>(() => nonNumeric.GetValue<long>());
        Assert.Throws<NotSupportedException>(() => nonBoolean.GetValue<bool>());
        Assert.Equal("alpha", nonNumeric.ToString());
    }

    [Theory]
    [InlineData("{\"jsonrpc\":\"2.0\",\"id\":\"abc\",\"method\":\"m\"}", "abc", false)]
    [InlineData("{\"jsonrpc\":\"2.0\",\"id\":77,\"method\":\"m\"}", "77", true)]
    public void JsonRpcIdConverter_DeserializesExpectedShape(string json, string expectedValue, bool expectedNumeric)
    {
        var envelope = JsonSerializer.Deserialize(json, AcpJsonContext.Default.JsonRpcEnvelope);

        Assert.NotNull(envelope);
        Assert.Equal(expectedValue, envelope.Id?.RawValue);
        Assert.Equal(expectedNumeric, envelope.Id?.IsNumeric);
    }

    [Theory]
    [InlineData("{\"jsonrpc\":\"2.0\",\"id\":12.5,\"method\":\"m\"}", "12.5")]
    [InlineData("{\"jsonrpc\":\"2.0\",\"id\":900719925474099312345,\"method\":\"m\"}", "900719925474099312345")]
    public void JsonRpcIdConverter_DeserializesNonInt64NumericIds(string json, string expectedRawValue)
    {
        var envelope = JsonSerializer.Deserialize(json, AcpJsonContext.Default.JsonRpcEnvelope);

        Assert.NotNull(envelope);
        Assert.Equal(expectedRawValue, envelope.Id?.RawValue);
        Assert.True(envelope.Id?.IsNumeric);
    }

    [Fact]
    public void JsonRpcIdConverter_SerializesStringAndNumericIds()
    {
        var stringEnvelope = new JsonRpcEnvelope
        {
            Id = "abc",
            Method = "m",
        };
        var numericEnvelope = new JsonRpcEnvelope
        {
            Id = 12,
            Method = "m",
        };

        var stringJson = JsonSerializer.Serialize(stringEnvelope, AcpJsonContext.Default.JsonRpcEnvelope);
        var numericJson = JsonSerializer.Serialize(numericEnvelope, AcpJsonContext.Default.JsonRpcEnvelope);

        Assert.Contains("\"id\":\"abc\"", stringJson, StringComparison.Ordinal);
        Assert.Contains("\"id\":12", numericJson, StringComparison.Ordinal);
    }

    [Fact]
    public void JsonRpcIdConverter_Read_WithMultiSegmentNumber_ParsesNumericId()
    {
        var converter = new JsonRpcIdConverter();
        var sequence = CreateReadOnlySequence(Encoding.UTF8.GetBytes("12"), Encoding.UTF8.GetBytes("34"));
        var reader = new Utf8JsonReader(sequence, isFinalBlock: true, state: default);
        Assert.True(reader.Read());

        var id = converter.Read(ref reader, typeof(JsonRpcId), new JsonSerializerOptions());

        Assert.Equal("1234", id.RawValue);
        Assert.True(id.IsNumeric);
    }

    [Fact]
    public void JsonRpcData_IndexersAndTypedAccess_Work()
    {
        using var document = JsonDocument.Parse("""{"name":"alpha","count":2,"ok":true,"nested":{"value":"x"},"items":[10,20]}""");
        var payload = JsonRpcData.FromJsonElement(document.RootElement);

        Assert.Equal("alpha", payload["name"]?.GetValue<string>());
        Assert.Equal(2, payload["count"]?.GetValue<int>());
        Assert.True(payload["ok"]?.GetValue<bool>());
        Assert.Equal("x", payload["nested"]?["value"]?.GetValue<string>());
        Assert.Equal(10, payload["items"]?[0]?.GetValue<int>());
        Assert.Null(payload["missing"]);
        Assert.Null(payload[99]);
    }

    [Fact]
    public void JsonRpcData_GetValueAndTryGetValue_HandleSuccessAndFailure()
    {
        var stringPayload = JsonRpcData.FromJsonElement(JsonSerializer.SerializeToElement("hello"));
        var numberPayload = JsonRpcData.FromJsonElement(JsonSerializer.SerializeToElement(7));
        var objectPayload = JsonRpcData.FromJsonElement(JsonSerializer.SerializeToElement(new { value = "x" }));

        Assert.Equal("hello", stringPayload.GetValue<string>());
        Assert.Equal(7, numberPayload.GetValue<int>());
        Assert.True(numberPayload.TryGetValue<int>(out var parsed));
        Assert.Equal(7, parsed);
        Assert.False(objectPayload.TryGetValue<int>(out _));
        Assert.Throws<NotSupportedException>(() => objectPayload.GetValue<int>());
    }

    [Fact]
    public void JsonRpcData_IndexerOnScalar_ReturnsNull()
    {
        var scalar = JsonRpcData.FromJsonElement(JsonSerializer.SerializeToElement("hello"));

        Assert.Null(scalar["anything"]);
        Assert.Null(scalar[0]);
    }

    [Fact]
    public void JsonRpcData_GetValue_WithOverflowingNumber_ThrowsNotSupported()
    {
        var payload = JsonRpcData.FromJsonElement(JsonSerializer.SerializeToElement(long.MaxValue));

        Assert.Throws<NotSupportedException>(() => payload.GetValue<int>());
    }

    [Fact]
    public void JsonRpcData_GetValue_WithBooleanFalse_ReturnsFalse()
    {
        var payload = JsonRpcData.FromJsonElement(JsonSerializer.SerializeToElement(false));

        Assert.False(payload.GetValue<bool>());
    }

    [Fact]
    public void JsonRpcData_GetValue_WithNullString_ReturnsNull_AndTryGetValueReturnsFalse()
    {
        var nullStringPayload = JsonRpcData.FromJsonElement(JsonSerializer.SerializeToElement<string?>(null));

        Assert.Throws<NotSupportedException>(() => nullStringPayload.GetValue<string>());
        Assert.False(nullStringPayload.TryGetValue<string>(out _));
    }

    [Fact]
    public void JsonRpcData_GetValue_WithUnsupportedType_Throws()
    {
        var payload = JsonRpcData.FromJsonElement(JsonSerializer.SerializeToElement("value"));

        Assert.Throws<NotSupportedException>(() => payload.GetValue<Guid>());
    }

    [Fact]
    public void JsonRpcIdConverter_ThrowsForBooleanToken()
    {
        const string json = """{"jsonrpc":"2.0","id":true,"method":"m"}""";

        Assert.Throws<JsonException>(() => JsonSerializer.Deserialize(json, AcpJsonContext.Default.JsonRpcEnvelope));
    }

    [Fact]
    public void JsonRpcIdConverter_SerializesNumericFlagWithNonNumericValue_AsString()
    {
        var envelope = new JsonRpcEnvelope
        {
            Id = new JsonRpcId("abc", IsNumeric: true),
            Method = "m",
        };

        var json = JsonSerializer.Serialize(envelope, AcpJsonContext.Default.JsonRpcEnvelope);
        Assert.Contains("\"id\":\"abc\"", json, StringComparison.Ordinal);
    }

    [Fact]
    public void JsonRpcIdConverter_SerializesNumericFlagWithDecimalValue_AsNumber()
    {
        var envelope = new JsonRpcEnvelope
        {
            Id = new JsonRpcId("12.5", IsNumeric: true),
            Method = "m",
        };

        var json = JsonSerializer.Serialize(envelope, AcpJsonContext.Default.JsonRpcEnvelope);
        Assert.Contains("\"id\":12.5", json, StringComparison.Ordinal);
    }

    [Fact]
    public void JsonRpcDataConverter_RoundTripsPayload()
    {
        var payload = JsonRpcData.FromJsonElement(JsonSerializer.SerializeToElement(new { sessionId = "s-1", ok = true }));
        var envelope = new JsonRpcEnvelope
        {
            Id = "req-1",
            Result = payload,
        };

        var json = JsonSerializer.Serialize(envelope, AcpJsonContext.Default.JsonRpcEnvelope);
        var restored = JsonSerializer.Deserialize(json, AcpJsonContext.Default.JsonRpcEnvelope);

        Assert.NotNull(restored);
        Assert.Equal("s-1", restored.Result?["sessionId"]?.GetValue<string>());
        Assert.True(restored.Result?["ok"]?.GetValue<bool>());
    }

    [Fact]
    public void JsonRpcData_ToJsonElement_ReturnsClonedElement()
    {
        var root = JsonSerializer.SerializeToElement(new { key = "value" });
        JsonRpcData payload = root;
        var converted = JsonRpcData.ToJsonElement(payload);

        Assert.Equal(JsonValueKind.Object, converted.ValueKind);
        Assert.Equal("value", converted.GetProperty("key").GetString());
    }

    [Fact]
    public void JsonRpcData_FromJsonElement_ConvertsPayload()
    {
        using var document = JsonDocument.Parse("""{"name":"value"}""");
        var payload = JsonRpcData.FromJsonElement(document.RootElement);
        Assert.Equal("value", payload["name"]?.GetValue<string>());
    }

    [Fact]
    public void JsonRpcData_LongAndDecimalAccessors_Work()
    {
        var longPayload = JsonRpcData.FromJsonElement(JsonSerializer.SerializeToElement(1234567890123L));
        var decimalPayload = JsonRpcData.FromJsonElement(JsonSerializer.SerializeToElement(12.34m));

        Assert.Equal(1234567890123L, longPayload.GetValue<long>());
        Assert.Equal(12.34m, decimalPayload.GetValue<decimal>());
    }

    [Fact]
    public void JsonRpcData_ImplicitJsonElementConversion_Works()
    {
        var payload = JsonRpcData.FromJsonElement(JsonSerializer.SerializeToElement(new { name = "alpha" }));
        JsonElement element = payload;

        Assert.Equal(JsonValueKind.Object, element.ValueKind);
        Assert.Equal("alpha", element.GetProperty("name").GetString());
    }

    [Fact]
    public void JsonRpcData_FromJsonNode_AndImplicitNodeConversion_Work()
    {
        var node = JsonNode.Parse("""{"sessionId":"s-42","nested":{"ok":true}}""");
        Assert.NotNull(node);

        var explicitPayload = JsonRpcData.FromJsonNode(node!);
        JsonRpcData implicitPayload = node!;

        Assert.Equal("s-42", explicitPayload["sessionId"]?.GetValue<string>());
        Assert.True(implicitPayload["nested"]?["ok"]?.GetValue<bool>());
    }

    [Fact]
    public void JsonRpcData_FromJsonNode_WithNullNode_Throws()
    {
        Assert.Throws<ArgumentNullException>(() => JsonRpcData.FromJsonNode(node: null!));
    }

    private static ReadOnlySequence<byte> CreateReadOnlySequence(byte[] first, byte[] second)
    {
        var firstSegment = new BufferSegment(first);
        var secondSegment = firstSegment.Append(second);
        return new ReadOnlySequence<byte>(firstSegment, 0, secondSegment, second.Length);
    }

    private sealed class BufferSegment : ReadOnlySequenceSegment<byte>
    {
        public BufferSegment(ReadOnlyMemory<byte> memory) => Memory = memory;

        public BufferSegment Append(ReadOnlyMemory<byte> nextMemory)
        {
            var next = new BufferSegment(nextMemory)
            {
                RunningIndex = RunningIndex + Memory.Length,
            };
            Next = next;
            return next;
        }
    }
}
