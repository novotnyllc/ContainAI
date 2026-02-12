using ContainAI.Cli.Host.ContainerRuntime.Models;

namespace ContainAI.Cli.Host.ContainerRuntime.Infrastructure;

internal interface IContainerRuntimePrivilegedCommandService
{
    Task RunAsRootAsync(string executable, IReadOnlyList<string> arguments);

    Task<ProcessCaptureResult> RunAsRootCaptureAsync(
        string executable,
        IReadOnlyList<string> arguments,
        string? standardInput,
        CancellationToken cancellationToken);
}
