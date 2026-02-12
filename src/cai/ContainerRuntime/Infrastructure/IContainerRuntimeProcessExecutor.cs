using ContainAI.Cli.Host.ContainerRuntime.Models;

namespace ContainAI.Cli.Host.ContainerRuntime.Infrastructure;

internal interface IContainerRuntimeProcessExecutor
{
    Task<ProcessCaptureResult> RunCaptureAsync(
        string executable,
        IReadOnlyList<string> arguments,
        string? workingDirectory,
        CancellationToken cancellationToken,
        string? standardInput = null);
}
