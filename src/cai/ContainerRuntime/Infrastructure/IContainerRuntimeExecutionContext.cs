using ContainAI.Cli.Host.ContainerRuntime.Models;

namespace ContainAI.Cli.Host.ContainerRuntime.Infrastructure;

internal interface IContainerRuntimeExecutionContext
{
    TextWriter StandardOutput { get; }

    TextWriter StandardError { get; }

    IManifestTomlParser ManifestTomlParser { get; }

    Task LogInfoAsync(bool quiet, string message);

    Task RunAsRootAsync(string executable, IReadOnlyList<string> arguments);

    Task<ProcessCaptureResult> RunAsRootCaptureAsync(
        string executable,
        IReadOnlyList<string> arguments,
        string? standardInput,
        CancellationToken cancellationToken);

    Task<ProcessCaptureResult> RunProcessCaptureAsync(
        string executable,
        IReadOnlyList<string> arguments,
        string? workingDirectory,
        CancellationToken cancellationToken,
        string? standardInput = null);

    Task<bool> IsSymlinkAsync(string path);

    Task<string?> ReadLinkTargetAsync(string path);

    Task<string?> TryReadTrimmedTextAsync(string path);

    Task WriteTimestampAsync(string path);

    void EnsureFileWithContent(string path, string? content);

    bool IsExecutable(string path);
}
