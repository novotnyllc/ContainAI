using ContainAI.Cli.Abstractions;
using ContainAI.Cli.Host.RuntimeSupport.Models;
using ContainAI.Cli.Host.RuntimeSupport.Process;

namespace ContainAI.Cli.Host.RuntimeSupport.Docker;

internal static class CaiRuntimeDockerHelpers
{
    private static readonly string[] PreferredDockerContexts =
    [
        "containai-docker",
        "containai-secure",
        "docker-containai",
    ];

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
        var context = await ResolveDockerContextAsync(cancellationToken).ConfigureAwait(false);
        var dockerArgs = PrependContextIfNeeded(context, args);
        return await CaiRuntimeProcessRunner.RunProcessCaptureAsync("docker", dockerArgs, cancellationToken).ConfigureAwait(false);
    }

    internal static async Task<RuntimeProcessResult> DockerCaptureAsync(IReadOnlyList<string> args, string standardInput, CancellationToken cancellationToken)
    {
        var context = await ResolveDockerContextAsync(cancellationToken).ConfigureAwait(false);
        var dockerArgs = PrependContextIfNeeded(context, args);
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

    internal static async Task<string?> ResolveDockerContextAsync(CancellationToken cancellationToken)
    {
        foreach (var contextName in PreferredDockerContexts)
        {
            var probe = await CaiRuntimeProcessRunner
                .RunProcessCaptureAsync("docker", ["context", "inspect", contextName], cancellationToken)
                .ConfigureAwait(false);
            if (probe.ExitCode == 0)
            {
                return contextName;
            }
        }

        return null;
    }

    internal static async Task<List<string>> FindContainerContextsAsync(string containerName, CancellationToken cancellationToken)
    {
        var contexts = new List<string>();
        foreach (var contextName in await GetAvailableContextsAsync(cancellationToken).ConfigureAwait(false))
        {
            var inspectArgs = new List<string>();
            if (!string.Equals(contextName, "default", StringComparison.Ordinal))
            {
                inspectArgs.Add("--context");
                inspectArgs.Add(contextName);
            }

            inspectArgs.AddRange(["inspect", "--type", "container", "--", containerName]);
            var inspect = await CaiRuntimeProcessRunner.RunProcessCaptureAsync("docker", inspectArgs, cancellationToken).ConfigureAwait(false);
            if (inspect.ExitCode == 0)
            {
                contexts.Add(contextName);
            }
        }

        return contexts;
    }

    internal static async Task<List<string>> GetAvailableContextsAsync(CancellationToken cancellationToken)
    {
        var contexts = new List<string>();
        foreach (var contextName in PreferredDockerContexts)
        {
            var probe = await CaiRuntimeProcessRunner
                .RunProcessCaptureAsync("docker", ["context", "inspect", contextName], cancellationToken)
                .ConfigureAwait(false);
            if (probe.ExitCode == 0)
            {
                contexts.Add(contextName);
            }
        }

        contexts.Add("default");
        return contexts;
    }

    internal static async Task<RuntimeProcessResult> DockerCaptureForContextAsync(string context, IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        var dockerArgs = new List<string>();
        if (!string.Equals(context, "default", StringComparison.Ordinal))
        {
            dockerArgs.Add("--context");
            dockerArgs.Add(context);
        }

        dockerArgs.AddRange(args);
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

    private static List<string> PrependContextIfNeeded(string? context, IReadOnlyList<string> args)
    {
        var dockerArgs = new List<string>();
        if (!string.IsNullOrWhiteSpace(context))
        {
            dockerArgs.Add("--context");
            dockerArgs.Add(context);
        }

        dockerArgs.AddRange(args);
        return dockerArgs;
    }
}
