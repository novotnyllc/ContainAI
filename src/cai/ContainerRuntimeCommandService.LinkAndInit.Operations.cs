namespace ContainAI.Cli.Host.ContainerRuntime.Infrastructure;

using ContainAI.Cli.Host.ContainerRuntime.Models;

internal sealed partial class ContainerRuntimeExecutionContext
{
    public Task RunAsRootAsync(string executable, IReadOnlyList<string> arguments)
        => privilegedCommandService.RunAsRootAsync(executable, arguments);

    public Task<ProcessCaptureResult> RunAsRootCaptureAsync(
        string executable,
        IReadOnlyList<string> arguments,
        string? standardInput,
        CancellationToken cancellationToken)
        => privilegedCommandService.RunAsRootCaptureAsync(executable, arguments, standardInput, cancellationToken);

    public Task<ProcessCaptureResult> RunProcessCaptureAsync(
        string executable,
        IReadOnlyList<string> arguments,
        string? workingDirectory,
        CancellationToken cancellationToken,
        string? standardInput = null)
        => processExecutor.RunCaptureAsync(executable, arguments, workingDirectory, cancellationToken, standardInput);

    public Task<bool> IsSymlinkAsync(string path)
        => fileSystemService.IsSymlinkAsync(path);

    public Task<string?> ReadLinkTargetAsync(string path)
        => fileSystemService.ReadLinkTargetAsync(path);

    public Task<string?> TryReadTrimmedTextAsync(string path)
        => fileSystemService.TryReadTrimmedTextAsync(path);

    public Task WriteTimestampAsync(string path)
        => fileSystemService.WriteTimestampAsync(path);

    public void EnsureFileWithContent(string path, string? content)
        => fileSystemService.EnsureFileWithContent(path, content);

    public bool IsExecutable(string path)
        => fileSystemService.IsExecutable(path);
}
