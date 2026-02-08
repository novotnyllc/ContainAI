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
    public void JsonRpcData_FromJsonNode_ConvertsNodePayload()
    {
        var node = JsonNode.Parse("""{"name":"value"}""");
        Assert.NotNull(node);

        var payload = JsonRpcData.FromJsonNode(node);
        Assert.Equal("value", payload["name"]?.GetValue<string>());
    }
}
