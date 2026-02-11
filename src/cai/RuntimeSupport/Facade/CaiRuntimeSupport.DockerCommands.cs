using ContainAI.Cli.Abstractions;
using ContainAI.Cli.Host.RuntimeSupport.Docker;

namespace ContainAI.Cli.Host;

internal abstract partial class CaiRuntimeSupport
{
    protected static Task<bool> DockerContainerExistsAsync(string containerName, CancellationToken cancellationToken)
        => CaiRuntimeDockerHelpers.DockerContainerExistsAsync(containerName, cancellationToken);

    protected static Task<int> DockerRunAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => CaiRuntimeDockerHelpers.DockerRunAsync(args, cancellationToken);

    protected static async Task<ProcessResult> DockerCaptureAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        var result = await CaiRuntimeDockerHelpers.DockerCaptureAsync(args, cancellationToken).ConfigureAwait(false);
        return ToProcessResult(result);
    }

    protected static async Task<ProcessResult> DockerCaptureAsync(IReadOnlyList<string> args, string standardInput, CancellationToken cancellationToken)
    {
        var result = await CaiRuntimeDockerHelpers.DockerCaptureAsync(args, standardInput, cancellationToken).ConfigureAwait(false);
        return ToProcessResult(result);
    }

    protected static Task<CommandExecutionResult> ExecuteDockerCommandAsync(
        IReadOnlyList<string> args,
        string? standardInput,
        CancellationToken cancellationToken)
        => CaiRuntimeDockerHelpers.ExecuteDockerCommandAsync(args, standardInput, cancellationToken);

    protected static Task<string?> ResolveDockerContextAsync(CancellationToken cancellationToken)
        => CaiRuntimeDockerHelpers.ResolveDockerContextAsync(cancellationToken);

    protected static Task<List<string>> FindContainerContextsAsync(string containerName, CancellationToken cancellationToken)
        => CaiRuntimeDockerHelpers.FindContainerContextsAsync(containerName, cancellationToken);

    protected static Task<List<string>> GetAvailableContextsAsync(CancellationToken cancellationToken)
        => CaiRuntimeDockerHelpers.GetAvailableContextsAsync(cancellationToken);

    protected static async Task<ProcessResult> DockerCaptureForContextAsync(string context, IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        var result = await CaiRuntimeDockerHelpers.DockerCaptureForContextAsync(context, args, cancellationToken).ConfigureAwait(false);
        return ToProcessResult(result);
    }

    protected static Task<string?> ResolveDataVolumeFromContainerAsync(string containerName, string? explicitVolume, CancellationToken cancellationToken)
        => CaiRuntimeDockerHelpers.ResolveDataVolumeFromContainerAsync(containerName, explicitVolume, cancellationToken);
}
