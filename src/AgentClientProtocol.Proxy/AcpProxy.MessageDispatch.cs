using System.Text.Json;
using AgentClientProtocol.Proxy.Protocol;

namespace AgentClientProtocol.Proxy;

public sealed partial class AcpProxy
{
    private async Task ProcessMessageAsync(string line)
    {
        var message = JsonSerializer.Deserialize(line, AcpJsonContext.Default.JsonRpcEnvelope);
        if (message == null || IsEditorResponse(message))
        {
            return;
        }

        try
        {
            await DispatchEditorMessageAsync(message).ConfigureAwait(false);
        }
        catch (JsonException ex)
        {
            if (message.Id != null)
            {
                await output.EnqueueAsync(JsonRpcHelpers.CreateErrorResponse(
                    message.Id,
                    JsonRpcErrorCodes.InvalidParams,
                    $"Invalid params: {ex.Message}")).ConfigureAwait(false);
                return;
            }

            await errorSink.WriteLineAsync($"Malformed notification params skipped: {ex.Message}").ConfigureAwait(false);
        }
    }

    private static bool IsEditorResponse(JsonRpcEnvelope message)
        => message.Method == null && message.Id != null && (message.Result != null || message.Error != null);

    private async Task DispatchEditorMessageAsync(JsonRpcEnvelope message)
    {
        switch (message.Method)
        {
            case "initialize":
                await HandleInitializeAsync(message).ConfigureAwait(false);
                return;

            case "session/new":
                await HandleSessionNewAsync(message).ConfigureAwait(false);
                return;

            case "session/prompt":
            case "session/end":
                await RouteToSessionAsync(message).ConfigureAwait(false);
                return;

            default:
                await HandleUnknownMethodAsync(message).ConfigureAwait(false);
                return;
        }
    }

    private async Task HandleUnknownMethodAsync(JsonRpcEnvelope message)
    {
        if (message.Id == null)
        {
            return;
        }

        await output.EnqueueAsync(JsonRpcHelpers.CreateErrorResponse(
            message.Id,
            JsonRpcErrorCodes.MethodNotFound,
            $"Method not found: {message.Method}")).ConfigureAwait(false);
    }
}
