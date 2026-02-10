using System.Text;
using System.Text.Json;

namespace AgentClientProtocol.Proxy;

public sealed partial class AcpProxy
{
    /// <summary>
    /// Runs the proxy, reading from stdin until EOF or cancellation.
    /// </summary>
    public async Task<int> RunAsync(Stream stdin, CancellationToken cancellationToken = default)
    {
        using var linkedCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, cts.Token);
        var ct = linkedCts.Token;
        var writerTask = output.RunAsync(ct);

        try
        {
            await RunInputLoopAsync(stdin, ct).ConfigureAwait(false);
            await ShutdownAsync().ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is InvalidOperationException or IOException or UnauthorizedAccessException)
        {
            await errorSink.WriteLineAsync($"Fatal error: {ex.Message}").ConfigureAwait(false);
            return 1;
        }
        finally
        {
            output.Complete();
            try
            {
                await writerTask.ConfigureAwait(false);
            }
            catch (OperationCanceledException ex)
            {
                await errorSink.WriteLineAsync($"Output flush canceled: {ex.Message}").ConfigureAwait(false);
            }

            await cts.CancelAsync().ConfigureAwait(false);
        }

        return 0;
    }

    private async Task RunInputLoopAsync(Stream stdin, CancellationToken cancellationToken)
    {
        using var reader = new StreamReader(stdin, Encoding.UTF8);
        while (!cancellationToken.IsCancellationRequested)
        {
            string? line;
            try
            {
                line = await reader.ReadLineAsync(cancellationToken).ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
                break;
            }

            if (line == null)
            {
                break;
            }

            if (string.IsNullOrWhiteSpace(line))
            {
                continue;
            }

            await TryProcessMessageAsync(line).ConfigureAwait(false);
        }
    }

    private async Task TryProcessMessageAsync(string line)
    {
        try
        {
            await ProcessMessageAsync(line).ConfigureAwait(false);
        }
        catch (JsonException ex)
        {
            await errorSink.WriteLineAsync($"JSON parse error: {ex.Message}").ConfigureAwait(false);
        }
        catch (InvalidOperationException ex)
        {
            await errorSink.WriteLineAsync($"Error processing message: {ex.Message}").ConfigureAwait(false);
        }
        catch (IOException ex)
        {
            await errorSink.WriteLineAsync($"Error processing message: {ex.Message}").ConfigureAwait(false);
        }
    }
}
