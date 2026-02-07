// Thread-safe output writer for JSON-RPC messages
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
    private static readonly byte[] NewLine = [(byte)'\n'];
    private readonly Channel<JsonRpcMessage> _channel = Channel.CreateBounded<JsonRpcMessage>(new BoundedChannelOptions(capacity: 1024)
    {
        SingleReader = true,
        SingleWriter = false,
        FullMode = BoundedChannelFullMode.Wait,
    });
    private readonly Stream _stdout;

    public OutputWriter(Stream stdout) => _stdout = stdout;

    /// <summary>
    /// Enqueues a message to be written to stdout.
    /// </summary>
    public async Task EnqueueAsync(JsonRpcMessage message, CancellationToken cancellationToken = default)
        => await _channel.Writer.WriteAsync(message, cancellationToken);

    /// <summary>
    /// Signals that no more messages will be enqueued.
    /// </summary>
    public void Complete() => _channel.Writer.Complete();

    /// <summary>
    /// Runs the output writer loop, writing messages to stdout as NDJSON.
    /// </summary>
    public async Task RunAsync(CancellationToken ct)
    {
        try
        {
            await foreach (var message in _channel.Reader.ReadAllAsync(ct))
            {
                var bytes = JsonSerializer.SerializeToUtf8Bytes(message, AcpJsonContext.Default.JsonRpcMessage);
                await _stdout.WriteAsync(bytes, ct);
                await _stdout.WriteAsync(NewLine, ct);
                await _stdout.FlushAsync(ct);
            }
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            return;
        }
    }
}
