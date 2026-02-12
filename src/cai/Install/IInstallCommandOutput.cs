namespace ContainAI.Cli.Host;

internal interface IInstallCommandOutput
{
    Task WriteInfoAsync(string message, CancellationToken cancellationToken);

    Task WriteSuccessAsync(string message, CancellationToken cancellationToken);

    Task WriteWarningAsync(string message, CancellationToken cancellationToken);

    Task WriteErrorAsync(string message, CancellationToken cancellationToken);

    Task WriteRawErrorAsync(string message, CancellationToken cancellationToken);
}
