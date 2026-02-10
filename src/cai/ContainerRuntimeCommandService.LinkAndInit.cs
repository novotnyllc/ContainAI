namespace ContainAI.Cli.Host.ContainerRuntime.Infrastructure;

using ContainAI.Cli.Host.ContainerRuntime.Models;

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
    {
        if (quiet)
        {
            return Task.CompletedTask;
        }

        return StandardOutput.WriteLineAsync($"[INFO] {message}");
    }

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
