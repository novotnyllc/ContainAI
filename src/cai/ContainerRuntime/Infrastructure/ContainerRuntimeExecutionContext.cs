using ContainAI.Cli.Host.ContainerRuntime.Models;

namespace ContainAI.Cli.Host.ContainerRuntime.Infrastructure;

internal sealed class ContainerRuntimeExecutionContext : IContainerRuntimeExecutionContext
{
    private readonly ContainerRuntimeProcessExecutor processExecutor;
    private readonly ContainerRuntimePrivilegedCommandService privilegedCommandService;
    private readonly ContainerRuntimeFileSystemService fileSystemService;

    public ContainerRuntimeExecutionContext(TextWriter standardOutput, TextWriter standardError, IManifestTomlParser manifestTomlParser)
    {
        StandardOutput = standardOutput;
        StandardError = standardError;
        ManifestTomlParser = manifestTomlParser ?? throw new ArgumentNullException(nameof(manifestTomlParser));
        processExecutor = new ContainerRuntimeProcessExecutor();
        privilegedCommandService = new ContainerRuntimePrivilegedCommandService(processExecutor);
        fileSystemService = new ContainerRuntimeFileSystemService(processExecutor);
    }

    public TextWriter StandardOutput { get; }

    public TextWriter StandardError { get; }

    public IManifestTomlParser ManifestTomlParser { get; }

    public Task LogInfoAsync(bool quiet, string message)
        => quiet
            ? Task.CompletedTask
            : StandardOutput.WriteLineAsync($"[INFO] {message}");

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
