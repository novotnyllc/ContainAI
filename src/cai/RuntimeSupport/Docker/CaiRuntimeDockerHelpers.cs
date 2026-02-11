using ContainAI.Cli.Abstractions;
using ContainAI.Cli.Host.RuntimeSupport.Models;
using ContainAI.Cli.Host.RuntimeSupport.Process;

namespace ContainAI.Cli.Host.RuntimeSupport.Docker;

internal static class CaiRuntimeDockerHelpers
{
    internal static async Task<bool> DockerContainerExistsAsync(string containerName, CancellationToken cancellationToken)
    {
        var result = await DockerRunAsync(["inspect", "--type", "container", containerName], cancellationToken).ConfigureAwait(false);
        return result == 0;
    }

    internal static async Task<int> DockerRunAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        var result = await DockerCaptureAsync(args, cancellationToken).ConfigureAwait(false);
        return result.ExitCode;
    }

    internal static async Task<RuntimeProcessResult> DockerCaptureAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        var context = await CaiRuntimeDockerContextResolver.ResolveDockerContextAsync(cancellationToken).ConfigureAwait(false);
        var dockerArgs = CaiRuntimeDockerContextResolver.PrependContextIfNeeded(context, args);
        return await CaiRuntimeProcessRunner.RunProcessCaptureAsync("docker", dockerArgs, cancellationToken).ConfigureAwait(false);
    }

    internal static async Task<RuntimeProcessResult> DockerCaptureAsync(IReadOnlyList<string> args, string standardInput, CancellationToken cancellationToken)
    {
        var context = await CaiRuntimeDockerContextResolver.ResolveDockerContextAsync(cancellationToken).ConfigureAwait(false);
        var dockerArgs = CaiRuntimeDockerContextResolver.PrependContextIfNeeded(context, args);
        return await CaiRuntimeProcessRunner.RunProcessCaptureAsync("docker", dockerArgs, cancellationToken, standardInput).ConfigureAwait(false);
    }

    internal static async Task<CommandExecutionResult> ExecuteDockerCommandAsync(
        IReadOnlyList<string> args,
        string? standardInput,
        CancellationToken cancellationToken)
    {
        var result = standardInput is null
            ? await DockerCaptureAsync(args, cancellationToken).ConfigureAwait(false)
            : await DockerCaptureAsync(args, standardInput, cancellationToken).ConfigureAwait(false);
        return new CommandExecutionResult(result.ExitCode, result.StandardOutput, result.StandardError);
    }

    internal static Task<string?> ResolveDockerContextAsync(CancellationToken cancellationToken)
        => CaiRuntimeDockerContextResolver.ResolveDockerContextAsync(cancellationToken);

    internal static Task<List<string>> FindContainerContextsAsync(string containerName, CancellationToken cancellationToken)
        => CaiRuntimeDockerContextResolver.FindContainerContextsAsync(containerName, cancellationToken);

    internal static Task<List<string>> GetAvailableContextsAsync(CancellationToken cancellationToken)
        => CaiRuntimeDockerContextResolver.GetAvailableContextsAsync(cancellationToken);

    internal static async Task<RuntimeProcessResult> DockerCaptureForContextAsync(string context, IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        var dockerArgs = CaiRuntimeDockerContextResolver.BuildDockerArgsForContext(context, args);
        return await CaiRuntimeProcessRunner.RunProcessCaptureAsync("docker", dockerArgs, cancellationToken).ConfigureAwait(false);
    }

    internal static async Task<string?> ResolveDataVolumeFromContainerAsync(string containerName, string? explicitVolume, CancellationToken cancellationToken)
    {
        if (!string.IsNullOrWhiteSpace(explicitVolume))
        {
            return explicitVolume;
        }

        var inspect = await DockerCaptureAsync(
            ["inspect", "--format", "{{range .Mounts}}{{if and (eq .Type \"volume\") (eq .Destination \"/mnt/agent-data\")}}{{.Name}}{{end}}{{end}}", containerName],
            cancellationToken).ConfigureAwait(false);

        if (inspect.ExitCode != 0)
        {
            return null;
        }

        var volumeName = inspect.StandardOutput.Trim();
        return string.IsNullOrWhiteSpace(volumeName) ? null : volumeName;
    }
}
