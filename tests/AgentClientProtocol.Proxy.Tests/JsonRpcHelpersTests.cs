using System.Text.Json.Nodes;
using AgentClientProtocol.Proxy.Protocol;
using Xunit;

namespace AgentClientProtocol.Proxy.Tests;

public class JsonRpcHelpersTests
{
    [Fact]
    public void NormalizeId_StringValue_ReturnsString()
    {
        var id = JsonValue.Create("request-123");

        var result = JsonRpcHelpers.NormalizeId(id);

        Assert.Equal("request-123", result);
    }

    [Fact]
    public void NormalizeId_IntegerValue_ReturnsStringOfNumber()
    {
        var id = JsonValue.Create(42);

        var result = JsonRpcHelpers.NormalizeId(id);

        Assert.Equal("42", result);
    }

    [Fact]
    public void NormalizeId_LongValue_ReturnsStringOfNumber()
    {
        var id = JsonValue.Create(9876543210L);

        var result = JsonRpcHelpers.NormalizeId(id);

        Assert.Equal("9876543210", result);
    }

    [Fact]
    public void NormalizeId_Null_ReturnsNull()
    {
        var result = JsonRpcHelpers.NormalizeId(null);

        Assert.Null(result);
    }

    [Fact]
    public void CreateErrorResponse_CreatesValidErrorMessage()
    {
        var id = JsonValue.Create("req-1");

        var result = JsonRpcHelpers.CreateErrorResponse(id, -32601, "Method not found");

        Assert.Equal("2.0", result.JsonRpc);
        Assert.NotNull(result.Error);
        Assert.Equal(-32601, result.Error.Code);
        Assert.Equal("Method not found", result.Error.Message);
        Assert.Null(result.Result);
        Assert.Null(result.Method);
    }

    [Fact]
    public void CreateErrorResponse_WithData_IncludesData()
    {
        var id = JsonValue.Create("req-2");
        var data = new JsonObject { ["details"] = "Additional info" };

        var result = JsonRpcHelpers.CreateErrorResponse(id, -32000, "Server error", data);

        Assert.NotNull(result.Error);
        Assert.NotNull(result.Error.Data);
        var dataObj = Assert.IsType<JsonObject>(result.Error.Data);
        Assert.Equal("Additional info", dataObj["details"]?.GetValue<string>());
    }

    [Fact]
    public void CreateSuccessResponse_CreatesValidResponse()
    {
        var id = JsonValue.Create("req-3");
        var resultData = new JsonObject { ["sessionId"] = "session-123" };

        var result = JsonRpcHelpers.CreateSuccessResponse(id, resultData);

        Assert.Equal("2.0", result.JsonRpc);
        Assert.NotNull(result.Result);
        Assert.Null(result.Error);
        Assert.Null(result.Method);
        var resultObj = Assert.IsType<JsonObject>(result.Result);
        Assert.Equal("session-123", resultObj["sessionId"]?.GetValue<string>());
    }

    [Theory]
    [InlineData(-32700, "Parse error")]
    [InlineData(-32600, "Invalid Request")]
    [InlineData(-32601, "Method not found")]
    [InlineData(-32602, "Invalid params")]
    [InlineData(-32603, "Internal error")]
    public void JsonRpcErrorCodes_StandardCodes_HaveCorrectValues(int expectedCode, string description)
    {
        // This test documents the standard JSON-RPC 2.0 error codes
        // Reserved range is -32768 to -32000 per JSON-RPC spec
        _ = description; // Suppress unused variable warning

        Assert.True(expectedCode >= -32768 && expectedCode <= -32000,
            $"Code {expectedCode} should be in reserved range -32768 to -32000");
    }
}
