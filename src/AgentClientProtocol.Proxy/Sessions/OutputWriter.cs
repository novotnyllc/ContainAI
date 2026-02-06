// Thread-safe output writer for JSON-RPC messages
using System.Text;
using System.Text.Json;
using System.Threading.Channels;
using AgentClientProtocol.Proxy.Protocol;

namespace AgentClientProtocol.Proxy.Sessions;

/// <summary>
/// Thread-safe writer for NDJSON output to stdout.
/// Ensures messages from multiple sessions don't interleave.
/// </summary>
public sealed class OutputWriter
{
    private readonly Channel<JsonRpcMessage> _channel = Channel.CreateUnbounded<JsonRpcMessage>();
    private readonly Stream _stdout;

    public OutputWriter(Stream stdout) => _stdout = stdout;

    /// <summary>
    /// Enqueues a message to be written to stdout.
    /// </summary>
    public async Task EnqueueAsync(JsonRpcMessage message)
    {
        await _channel.Writer.WriteAsync(message);
    }

    /// <summary>
    /// Signals that no more messages will be enqueued.
    /// </summary>
    public void Complete()
    {
        _channel.Writer.Complete();
    }

    /// <summary>
    /// Runs the output writer loop, writing messages to stdout as NDJSON.
    /// </summary>
    public async Task RunAsync(CancellationToken ct)
    {
        try
        {
            await foreach (var message in _channel.Reader.ReadAllAsync(ct))
            {
                var json = JsonSerializer.Serialize(message, AcpJsonContext.Default.JsonRpcMessage);
                var bytes = Encoding.UTF8.GetBytes(json + "\n");
                await _stdout.WriteAsync(bytes, ct);
                await _stdout.FlushAsync(ct);
            }
        }
        catch (OperationCanceledException)
        {
            // Expected during shutdown
        }
    }
}
