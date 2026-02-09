namespace AgentClientProtocol.Proxy.Protocol;

/// <summary>
/// Standard JSON-RPC 2.0 error codes.
/// </summary>
public static class JsonRpcErrorCodes
{
    public const int ParseError = -32700;
    public const int InvalidRequest = -32600;
    public const int MethodNotFound = -32601;
    public const int InvalidParams = -32602;
    public const int InternalError = -32603;

    // Server-defined errors (reserved: -32000 to -32099)
    public const int SessionNotFound = -32001;
    public const int SessionCreationFailed = -32000;
}
