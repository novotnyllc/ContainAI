using System.Text.Json;
using System.Text.Json.Nodes;
using AgentClientProtocol.Proxy.Protocol;
using Xunit;

namespace AgentClientProtocol.Proxy.Tests;

public class JsonRpcMessageTests
{
    [Fact]
    public void Serialize_Request_IncludesRequiredFields()
    {
        var message = new JsonRpcMessage
        {
            Id = "req-1",
            Method = "initialize",
            Params = new JsonObject { ["protocolVersion"] = "2025-01-01" }
        };

        var json = JsonSerializer.Serialize(message, AcpJsonContext.Default.JsonRpcMessage);
        var parsed = JsonDocument.Parse(json);

        Assert.Equal("2.0", parsed.RootElement.GetProperty("jsonrpc").GetString());
        Assert.Equal("req-1", parsed.RootElement.GetProperty("id").GetString());
        Assert.Equal("initialize", parsed.RootElement.GetProperty("method").GetString());
        Assert.True(parsed.RootElement.TryGetProperty("params", out var paramsEl));
        Assert.Equal("2025-01-01", paramsEl.GetProperty("protocolVersion").GetString());
    }

    [Fact]
    public void Serialize_Response_ExcludesNullFields()
    {
        var message = new JsonRpcMessage
        {
            Id = "req-1",
            Result = new JsonObject { ["sessionId"] = "sess-123" }
        };

        var json = JsonSerializer.Serialize(message, AcpJsonContext.Default.JsonRpcMessage);
        var parsed = JsonDocument.Parse(json);

        Assert.Equal("2.0", parsed.RootElement.GetProperty("jsonrpc").GetString());
        Assert.Equal("req-1", parsed.RootElement.GetProperty("id").GetString());
        Assert.True(parsed.RootElement.TryGetProperty("result", out _));
        Assert.False(parsed.RootElement.TryGetProperty("method", out _));
        Assert.False(parsed.RootElement.TryGetProperty("error", out _));
        Assert.False(parsed.RootElement.TryGetProperty("params", out _));
    }

    [Fact]
    public void Serialize_Notification_ExcludesId()
    {
        var message = new JsonRpcMessage
        {
            Method = "session/end",
            Params = new JsonObject { ["sessionId"] = "sess-123" }
        };

        var json = JsonSerializer.Serialize(message, AcpJsonContext.Default.JsonRpcMessage);
        var parsed = JsonDocument.Parse(json);

        Assert.Equal("2.0", parsed.RootElement.GetProperty("jsonrpc").GetString());
        Assert.Equal("session/end", parsed.RootElement.GetProperty("method").GetString());
        Assert.False(parsed.RootElement.TryGetProperty("id", out _));
    }

    [Fact]
    public void Serialize_Error_IncludesErrorObject()
    {
        var message = new JsonRpcMessage
        {
            Id = "req-1",
            Error = new JsonRpcError
            {
                Code = -32601,
                Message = "Method not found"
            }
        };

        var json = JsonSerializer.Serialize(message, AcpJsonContext.Default.JsonRpcMessage);
        var parsed = JsonDocument.Parse(json);

        var error = parsed.RootElement.GetProperty("error");
        Assert.Equal(-32601, error.GetProperty("code").GetInt32());
        Assert.Equal("Method not found", error.GetProperty("message").GetString());
    }

    [Fact]
    public void Deserialize_Request_ParsesCorrectly()
    {
        var json = """{"jsonrpc":"2.0","id":"req-1","method":"initialize","params":{"protocolVersion":"2025-01-01"}}""";

        var message = JsonSerializer.Deserialize(json, AcpJsonContext.Default.JsonRpcMessage);

        Assert.NotNull(message);
        Assert.Equal("2.0", message.JsonRpc);
        Assert.Equal("initialize", message.Method);
        Assert.NotNull(message.Id);
        Assert.NotNull(message.Params);
    }

    [Fact]
    public void Deserialize_NumericId_PreservesType()
    {
        var json = """{"jsonrpc":"2.0","id":123,"method":"test"}""";

        var message = JsonSerializer.Deserialize(json, AcpJsonContext.Default.JsonRpcMessage);

        Assert.NotNull(message);
        Assert.NotNull(message.Id);

        // Verify we can extract the numeric value
        var idValue = message.Id as JsonValue;
        Assert.NotNull(idValue);
        Assert.True(idValue.TryGetValue<int>(out var intId));
        Assert.Equal(123, intId);
    }

    [Fact]
    public void Deserialize_Response_ParsesCorrectly()
    {
        var json = """{"jsonrpc":"2.0","id":"req-1","result":{"sessionId":"sess-abc"}}""";

        var message = JsonSerializer.Deserialize(json, AcpJsonContext.Default.JsonRpcMessage);

        Assert.NotNull(message);
        Assert.Equal("2.0", message.JsonRpc);
        Assert.NotNull(message.Result);
        Assert.Null(message.Error);
        Assert.Null(message.Method);
    }

    [Fact]
    public void Deserialize_Error_ParsesCorrectly()
    {
        var json = """{"jsonrpc":"2.0","id":"req-1","error":{"code":-32601,"message":"Method not found"}}""";

        var message = JsonSerializer.Deserialize(json, AcpJsonContext.Default.JsonRpcMessage);

        Assert.NotNull(message);
        Assert.NotNull(message.Error);
        Assert.Equal(-32601, message.Error.Code);
        Assert.Equal("Method not found", message.Error.Message);
    }

    [Fact]
    public void RoundTrip_PreservesAllFields()
    {
        var original = new JsonRpcMessage
        {
            Id = "test-id",
            Method = "test/method",
            Params = new JsonObject
            {
                ["stringVal"] = "hello",
                ["numVal"] = 42,
                ["nested"] = new JsonObject { ["inner"] = true }
            }
        };

        var json = JsonSerializer.Serialize(original, AcpJsonContext.Default.JsonRpcMessage);
        var restored = JsonSerializer.Deserialize(json, AcpJsonContext.Default.JsonRpcMessage);

        Assert.NotNull(restored);
        Assert.Equal(original.JsonRpc, restored.JsonRpc);
        Assert.Equal(original.Method, restored.Method);

        var originalParams = original.Params as JsonObject;
        var restoredParams = restored.Params as JsonObject;
        Assert.NotNull(restoredParams);
        Assert.Equal(originalParams?["stringVal"]?.GetValue<string>(), restoredParams["stringVal"]?.GetValue<string>());
        Assert.Equal(originalParams?["numVal"]?.GetValue<int>(), restoredParams["numVal"]?.GetValue<int>());
    }
}
