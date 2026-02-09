namespace ContainAI.Cli.Host;

internal sealed partial class InstallCommandRuntime
{
    private Task WriteInfoAsync(string message, CancellationToken cancellationToken)
        => WriteLineAsync(stdout, "INFO", message, cancellationToken);

    private Task WriteSuccessAsync(string message, CancellationToken cancellationToken)
        => WriteLineAsync(stdout, "OK", message, cancellationToken);

    private Task WriteWarningAsync(string message, CancellationToken cancellationToken)
        => WriteLineAsync(stderr, "WARN", message, cancellationToken);

    private Task WriteErrorAsync(string message, CancellationToken cancellationToken)
        => WriteLineAsync(stderr, "ERROR", message, cancellationToken);

    private static async Task WriteLineAsync(TextWriter writer, string level, string message, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        await writer.WriteLineAsync($"[{level}] {message}").ConfigureAwait(false);
    }
}
