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
    private readonly Channel<JsonRpcEnvelope> channel = Channel.CreateBounded<JsonRpcEnvelope>(new BoundedChannelOptions(capacity: 1024)
    {
        SingleReader = true,
        SingleWriter = false,
        FullMode = BoundedChannelFullMode.Wait,
    });
    private readonly Stream stdout;

    public OutputWriter(Stream outputStream) => stdout = outputStream;

    /// <summary>
    /// Enqueues a message to be written to stdout.
    /// </summary>
    public async Task EnqueueAsync(JsonRpcEnvelope message, CancellationToken cancellationToken = default)
        => await channel.Writer.WriteAsync(message, cancellationToken).ConfigureAwait(false);

    /// <summary>
    /// Signals that no more messages will be enqueued.
    /// </summary>
    public void Complete() => channel.Writer.Complete();

    /// <summary>
    /// Runs the output writer loop, writing messages to stdout as NDJSON.
    /// </summary>
    public async Task RunAsync(CancellationToken ct)
    {
        try
        {
            await foreach (var message in channel.Reader.ReadAllAsync(ct).ConfigureAwait(false))
            {
                var bytes = JsonSerializer.SerializeToUtf8Bytes(message, AcpJsonContext.Default.JsonRpcEnvelope);
                await stdout.WriteAsync(bytes, ct).ConfigureAwait(false);
                await stdout.WriteAsync(NewLine, ct).ConfigureAwait(false);
                await stdout.FlushAsync(ct).ConfigureAwait(false);
            }
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            return;
        }
    }
}
