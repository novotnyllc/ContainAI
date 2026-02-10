namespace ContainAI.Cli.Host.ContainerRuntime.Infrastructure;

using ContainAI.Cli.Host.ContainerRuntime.Models;

internal interface IContainerRuntimePrivilegedCommandService
{
    Task RunAsRootAsync(string executable, IReadOnlyList<string> arguments);

    Task<ProcessCaptureResult> RunAsRootCaptureAsync(
        string executable,
        IReadOnlyList<string> arguments,
        string? standardInput,
        CancellationToken cancellationToken);
}

internal sealed partial class ContainerRuntimePrivilegedCommandService : IContainerRuntimePrivilegedCommandService
{
    private readonly IContainerRuntimeProcessExecutor processExecutor;

    public ContainerRuntimePrivilegedCommandService(IContainerRuntimeProcessExecutor processExecutor)
        => this.processExecutor = processExecutor ?? throw new ArgumentNullException(nameof(processExecutor));
}
