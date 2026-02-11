namespace ContainAI.Cli.Host;

internal sealed class AcpProxyOperationExecutor(TextWriter stderr)
{
    public async Task<int> ExecuteAsync(Func<Task<int>> operation, CancellationToken cancellationToken)
    {
        try
        {
            return await operation().ConfigureAwait(false);
        }
        catch (ArgumentException ex)
        {
            return await WriteErrorAndReturnAsync(ex.Message).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            return 0;
        }
        catch (InvalidOperationException ex)
        {
            return await WriteErrorAndReturnAsync(ex.Message).ConfigureAwait(false);
        }
        catch (IOException ex)
        {
            return await WriteErrorAndReturnAsync(ex.Message).ConfigureAwait(false);
        }
        catch (UnauthorizedAccessException ex)
        {
            return await WriteErrorAndReturnAsync(ex.Message).ConfigureAwait(false);
        }
        catch (NotSupportedException ex)
        {
            return await WriteErrorAndReturnAsync(ex.Message).ConfigureAwait(false);
        }
    }

    private async Task<int> WriteErrorAndReturnAsync(string message)
    {
        await stderr.WriteLineAsync(message).ConfigureAwait(false);
        return 1;
    }
}
