namespace ContainAI.Cli.Host;

internal interface IInstallCommandOutput
{
    Task WriteInfoAsync(string message, CancellationToken cancellationToken);

    Task WriteSuccessAsync(string message, CancellationToken cancellationToken);

    Task WriteWarningAsync(string message, CancellationToken cancellationToken);

    Task WriteErrorAsync(string message, CancellationToken cancellationToken);

    Task WriteRawErrorAsync(string message, CancellationToken cancellationToken);
}

internal sealed class InstallCommandOutput : IInstallCommandOutput
{
    private readonly TextWriter stdout;
    private readonly TextWriter stderr;

    public InstallCommandOutput(TextWriter standardOutput, TextWriter standardError)
    {
        stdout = standardOutput ?? throw new ArgumentNullException(nameof(standardOutput));
        stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));
    }

    public Task WriteInfoAsync(string message, CancellationToken cancellationToken)
        => WriteLineAsync(stdout, "INFO", message, cancellationToken);

    public Task WriteSuccessAsync(string message, CancellationToken cancellationToken)
        => WriteLineAsync(stdout, "OK", message, cancellationToken);

    public Task WriteWarningAsync(string message, CancellationToken cancellationToken)
        => WriteLineAsync(stderr, "WARN", message, cancellationToken);

    public Task WriteErrorAsync(string message, CancellationToken cancellationToken)
        => WriteLineAsync(stderr, "ERROR", message, cancellationToken);

    public async Task WriteRawErrorAsync(string message, CancellationToken cancellationToken)
    {
        _ = cancellationToken;
        await stderr.WriteLineAsync(message).ConfigureAwait(false);
    }

    private static async Task WriteLineAsync(TextWriter writer, string level, string message, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        await writer.WriteLineAsync($"[{level}] {message}").ConfigureAwait(false);
    }
}
