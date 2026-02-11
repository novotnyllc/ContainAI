using ContainAI.Cli.Abstractions;
using ContainAI.Cli.Host.RuntimeSupport.Docker.Execution;
using ContainAI.Cli.Host.RuntimeSupport.Docker.Inspection;
using ContainAI.Cli.Host.RuntimeSupport.Models;

namespace ContainAI.Cli.Host.RuntimeSupport.Docker;

internal static class CaiRuntimeDockerHelpers
{
    internal static Task<bool> DockerContainerExistsAsync(string containerName, CancellationToken cancellationToken)
        => CaiDockerContainerInspector.DockerContainerExistsAsync(containerName, cancellationToken);

    internal static Task<int> DockerRunAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => CaiDockerCommandRunner.DockerRunAsync(args, cancellationToken);

    internal static Task<RuntimeProcessResult> DockerCaptureAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => CaiDockerCommandRunner.DockerCaptureAsync(args, cancellationToken);

    internal static Task<RuntimeProcessResult> DockerCaptureAsync(
        IReadOnlyList<string> args,
        string standardInput,
        CancellationToken cancellationToken)
        => CaiDockerCommandRunner.DockerCaptureAsync(args, standardInput, cancellationToken);

    internal static Task<CommandExecutionResult> ExecuteDockerCommandAsync(
        IReadOnlyList<string> args,
        string? standardInput,
        CancellationToken cancellationToken)
        => CaiDockerCommandRunner.ExecuteDockerCommandAsync(args, standardInput, cancellationToken);

    internal static Task<string?> ResolveDockerContextAsync(CancellationToken cancellationToken)
        => CaiRuntimeDockerContextResolver.ResolveDockerContextAsync(cancellationToken);

    internal static Task<List<string>> FindContainerContextsAsync(string containerName, CancellationToken cancellationToken)
        => CaiRuntimeDockerContextResolver.FindContainerContextsAsync(containerName, cancellationToken);

    internal static Task<List<string>> GetAvailableContextsAsync(CancellationToken cancellationToken)
        => CaiRuntimeDockerContextResolver.GetAvailableContextsAsync(cancellationToken);

    internal static Task<RuntimeProcessResult> DockerCaptureForContextAsync(
        string context,
        IReadOnlyList<string> args,
        CancellationToken cancellationToken)
        => CaiDockerCommandRunner.DockerCaptureForContextAsync(context, args, cancellationToken);

    internal static Task<string?> ResolveDataVolumeFromContainerAsync(
        string containerName,
        string? explicitVolume,
        CancellationToken cancellationToken)
        => CaiDockerContainerInspector.ResolveDataVolumeFromContainerAsync(containerName, explicitVolume, cancellationToken);
}
