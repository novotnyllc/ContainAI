using System.Text.Json;
using System.Threading.Channels;
using AgentClientProtocol.Proxy.Protocol;

namespace AgentClientProtocol.Proxy.Sessions;

internal sealed class AcpSessionTransport : IDisposable
{
    private readonly SemaphoreSlim writeLock = new(1, 1);
    private readonly CancellationTokenSource cts;
    private ChannelWriter<string>? agentInput;

    public AcpSessionTransport(CancellationTokenSource cts)
    {
        ArgumentNullException.ThrowIfNull(cts);
        this.cts = cts;
    }

    public ChannelReader<string>? AgentOutput { get; private set; }

    public Task? AgentExecutionTask { get; private set; }

    public void Attach(
        ChannelWriter<string> input,
        ChannelReader<string> output,
        Task executionTask)
    {
        ArgumentNullException.ThrowIfNull(input);
        ArgumentNullException.ThrowIfNull(output);
        ArgumentNullException.ThrowIfNull(executionTask);

        agentInput = input;
        AgentOutput = output;
        AgentExecutionTask = executionTask;
    }

    public async Task WriteAsync(JsonRpcEnvelope message)
    {
        if (agentInput == null)
        {
            return;
        }

        await writeLock.WaitAsync().ConfigureAwait(false);
        try
        {
            var json = JsonSerializer.Serialize(message, AcpJsonContext.Default.JsonRpcEnvelope);
            await agentInput.WriteAsync(json, cts.Token).ConfigureAwait(false);
        }
        catch (ChannelClosedException)
        {
            if (!cts.IsCancellationRequested)
            {
                // Agent transport closed unexpectedly; cancel pending operations.
                await cts.CancelAsync().ConfigureAwait(false);
            }
        }
        finally
        {
            writeLock.Release();
        }
    }

    public void CompleteInput() => agentInput?.TryComplete();

    public void Dispose() => writeLock.Dispose();
}
