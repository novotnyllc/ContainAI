using ContainAI.Cli.Abstractions;
using ContainAI.Cli.Host.RuntimeSupport.Models;
using ContainAI.Cli.Host.RuntimeSupport.Process;

namespace ContainAI.Cli.Host.RuntimeSupport.Docker.Execution;

internal static class CaiDockerCommandRunner
{
    public static async Task<int> DockerRunAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        var result = await DockerCaptureAsync(args, cancellationToken).ConfigureAwait(false);
        return result.ExitCode;
    }

    public static async Task<RuntimeProcessResult> DockerCaptureAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        var context = await CaiRuntimeDockerContextResolver.ResolveDockerContextAsync(cancellationToken).ConfigureAwait(false);
        var dockerArgs = CaiRuntimeDockerContextResolver.PrependContextIfNeeded(context, args);
        return await CaiRuntimeProcessRunner.RunProcessCaptureAsync("docker", dockerArgs, cancellationToken).ConfigureAwait(false);
    }

    public static async Task<RuntimeProcessResult> DockerCaptureAsync(
        IReadOnlyList<string> args,
        string standardInput,
        CancellationToken cancellationToken)
    {
        var context = await CaiRuntimeDockerContextResolver.ResolveDockerContextAsync(cancellationToken).ConfigureAwait(false);
        var dockerArgs = CaiRuntimeDockerContextResolver.PrependContextIfNeeded(context, args);
        return await CaiRuntimeProcessRunner.RunProcessCaptureAsync("docker", dockerArgs, cancellationToken, standardInput).ConfigureAwait(false);
    }

    public static async Task<CommandExecutionResult> ExecuteDockerCommandAsync(
        IReadOnlyList<string> args,
        string? standardInput,
        CancellationToken cancellationToken)
    {
        var result = standardInput is null
            ? await DockerCaptureAsync(args, cancellationToken).ConfigureAwait(false)
            : await DockerCaptureAsync(args, standardInput, cancellationToken).ConfigureAwait(false);
        return new CommandExecutionResult(result.ExitCode, result.StandardOutput, result.StandardError);
    }

    public static async Task<RuntimeProcessResult> DockerCaptureForContextAsync(
        string context,
        IReadOnlyList<string> args,
        CancellationToken cancellationToken)
    {
        var dockerArgs = CaiRuntimeDockerContextResolver.BuildDockerArgsForContext(context, args);
        return await CaiRuntimeProcessRunner.RunProcessCaptureAsync("docker", dockerArgs, cancellationToken).ConfigureAwait(false);
    }
}
