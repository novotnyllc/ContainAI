using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal abstract partial class CaiRuntimeSupport
{
    protected static async Task<bool> DockerContainerExistsAsync(string containerName, CancellationToken cancellationToken)
    {
        var result = await DockerRunAsync(["inspect", "--type", "container", containerName], cancellationToken).ConfigureAwait(false);
        return result == 0;
    }

    protected static async Task<int> DockerRunAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        var result = await DockerCaptureAsync(args, cancellationToken).ConfigureAwait(false);
        return result.ExitCode;
    }

    protected static async Task<ProcessResult> DockerCaptureAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        var context = await ResolveDockerContextAsync(cancellationToken).ConfigureAwait(false);
        var dockerArgs = new List<string>();
        if (!string.IsNullOrWhiteSpace(context))
        {
            dockerArgs.Add("--context");
            dockerArgs.Add(context);
        }

        dockerArgs.AddRange(args);
        return await RunProcessCaptureAsync("docker", dockerArgs, cancellationToken).ConfigureAwait(false);
    }

    protected static async Task<ProcessResult> DockerCaptureAsync(IReadOnlyList<string> args, string standardInput, CancellationToken cancellationToken)
    {
        var context = await ResolveDockerContextAsync(cancellationToken).ConfigureAwait(false);
        var dockerArgs = new List<string>();
        if (!string.IsNullOrWhiteSpace(context))
        {
            dockerArgs.Add("--context");
            dockerArgs.Add(context);
        }

        dockerArgs.AddRange(args);
        return await RunProcessCaptureAsync("docker", dockerArgs, cancellationToken, standardInput).ConfigureAwait(false);
    }

    protected static async Task<CommandExecutionResult> ExecuteDockerCommandAsync(
        IReadOnlyList<string> args,
        string? standardInput,
        CancellationToken cancellationToken)
    {
        var result = standardInput is null
            ? await DockerCaptureAsync(args, cancellationToken).ConfigureAwait(false)
            : await DockerCaptureAsync(args, standardInput, cancellationToken).ConfigureAwait(false);
        return new CommandExecutionResult(result.ExitCode, result.StandardOutput, result.StandardError);
    }

    protected static async Task<string?> ResolveDockerContextAsync(CancellationToken cancellationToken)
    {
        foreach (var contextName in new[] { "containai-docker", "containai-secure", "docker-containai" })
        {
            var probe = await RunProcessCaptureAsync(
                "docker",
                ["context", "inspect", contextName],
                cancellationToken).ConfigureAwait(false);
            if (probe.ExitCode == 0)
            {
                return contextName;
            }
        }

        return null;
    }

    protected static async Task<List<string>> FindContainerContextsAsync(string containerName, CancellationToken cancellationToken)
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
            var inspect = await RunProcessCaptureAsync("docker", inspectArgs, cancellationToken).ConfigureAwait(false);
            if (inspect.ExitCode == 0)
            {
                contexts.Add(contextName);
            }
        }

        return contexts;
    }

    protected static async Task<List<string>> GetAvailableContextsAsync(CancellationToken cancellationToken)
    {
        var contexts = new List<string>();
        foreach (var contextName in new[] { "containai-docker", "containai-secure", "docker-containai" })
        {
            var probe = await RunProcessCaptureAsync("docker", ["context", "inspect", contextName], cancellationToken).ConfigureAwait(false);
            if (probe.ExitCode == 0)
            {
                contexts.Add(contextName);
            }
        }

        contexts.Add("default");
        return contexts;
    }

    protected static async Task<ProcessResult> DockerCaptureForContextAsync(string context, IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        var dockerArgs = new List<string>();
        if (!string.Equals(context, "default", StringComparison.Ordinal))
        {
            dockerArgs.Add("--context");
            dockerArgs.Add(context);
        }

        dockerArgs.AddRange(args);
        return await RunProcessCaptureAsync("docker", dockerArgs, cancellationToken).ConfigureAwait(false);
    }

    protected static async Task<string?> ResolveDataVolumeFromContainerAsync(string containerName, string? explicitVolume, CancellationToken cancellationToken)
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
