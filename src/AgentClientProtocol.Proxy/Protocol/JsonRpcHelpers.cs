// Helper methods for JSON-RPC message handling
using System.Text.Json;

namespace AgentClientProtocol.Proxy.Protocol;

/// <summary>
/// Helper methods for JSON-RPC protocol handling.
/// </summary>
public static class JsonRpcHelpers
{
    /// <summary>
    /// Normalizes a JSON-RPC ID to a string for use as dictionary key.
    /// </summary>
    public static string? NormalizeId(JsonRpcId? id)
        => id?.RawValue;

    /// <summary>
    /// Creates an error response for a request.
    /// </summary>
    public static JsonRpcEnvelope CreateErrorResponse(JsonRpcId? id, int code, string message, JsonRpcData? data = null)
        => new()
        {
            Id = id,
            Error = new JsonRpcError
            {
                Code = code,
                Message = message,
                Data = data
            }
        };

    /// <summary>
    /// Creates a success response for a request.
    /// </summary>
    public static JsonRpcEnvelope CreateSuccessResponse(JsonRpcId? id, JsonRpcData? result)
        => new()
        {
            Id = id,
            Result = result
        };
}
