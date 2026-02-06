// Helper methods for JSON-RPC message handling
using System.Text.Json.Nodes;

namespace AgentClientProtocol.Proxy.Protocol;

/// <summary>
/// Helper methods for JSON-RPC protocol handling.
/// </summary>
public static class JsonRpcHelpers
{
    /// <summary>
    /// Normalizes a JSON-RPC ID to a string for use as dictionary key.
    /// JSON-RPC allows IDs to be strings or numbers. JsonNode.ToString() returns
    /// JSON-encoded values (strings with quotes), so we extract the raw value.
    /// </summary>
    public static string? NormalizeId(JsonNode? id)
    {
        if (id == null)
            return null;

        // Try to get as string value (most common)
        if (id is JsonValue jsonValue)
        {
            if (jsonValue.TryGetValue<string>(out var strId))
                return strId;
            if (jsonValue.TryGetValue<long>(out var longId))
                return longId.ToString();
            if (jsonValue.TryGetValue<int>(out var intId))
                return intId.ToString();
        }

        // Fallback: use the raw JSON representation without quotes
        // This handles edge cases like decimal numbers
        return id.ToJsonString();
    }

    /// <summary>
    /// Creates an error response for a request.
    /// </summary>
    public static JsonRpcMessage CreateErrorResponse(JsonNode? id, int code, string message, JsonNode? data = null)
    {
        return new JsonRpcMessage
        {
            Id = id,
            Error = new JsonRpcError
            {
                Code = code,
                Message = message,
                Data = data
            }
        };
    }

    /// <summary>
    /// Creates a success response for a request.
    /// </summary>
    public static JsonRpcMessage CreateSuccessResponse(JsonNode? id, JsonNode? result)
    {
        return new JsonRpcMessage
        {
            Id = id,
            Result = result
        };
    }
}
