namespace ContainAI.Cli.Host.RuntimeSupport;

internal static partial class CaiRuntimeDockerHelpers
{
    internal static async Task<string?> ResolveDockerContextAsync(CancellationToken cancellationToken)
    {
        foreach (var contextName in PreferredDockerContexts)
        {
            var probe = await CaiRuntimeProcessHelpers
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
            var inspect = await CaiRuntimeProcessHelpers.RunProcessCaptureAsync("docker", inspectArgs, cancellationToken).ConfigureAwait(false);
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
            var probe = await CaiRuntimeProcessHelpers
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
        return await CaiRuntimeProcessHelpers.RunProcessCaptureAsync("docker", dockerArgs, cancellationToken).ConfigureAwait(false);
    }
}
