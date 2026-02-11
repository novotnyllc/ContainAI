namespace ContainAI.Cli.Host;

internal static partial class SessionRuntimeInfrastructure
{
    public static Task<ProcessResult> RunTomlAsync(Func<TomlCommandResult> operation, CancellationToken cancellationToken)
        => SessionRuntimeProcessHelpers.RunTomlAsync(operation, cancellationToken);

    public static Task<int> RunProcessInteractiveAsync(
        string fileName,
        IReadOnlyList<string> arguments,
        TextWriter errorWriter,
        CancellationToken cancellationToken)
        => SessionRuntimeProcessHelpers.RunProcessInteractiveAsync(fileName, arguments, errorWriter, cancellationToken);

    public static Task<ProcessResult> RunProcessCaptureAsync(
        string fileName,
        IReadOnlyList<string> arguments,
        CancellationToken cancellationToken)
        => SessionRuntimeProcessHelpers.RunProcessCaptureAsync(fileName, arguments, cancellationToken);
}
