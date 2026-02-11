using ContainAI.Cli.Host.RuntimeSupport.Process;

namespace ContainAI.Cli.Host.RuntimeSupport.Docker;

internal static class CaiRuntimeDockerContextResolver
{
    private static readonly string[] PreferredDockerContexts =
    [
        "containai-docker",
        "containai-secure",
        "docker-containai",
    ];

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
            var inspectArgs = BuildDockerArgsForContext(contextName, ["inspect", "--type", "container", "--", containerName]);
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

    internal static List<string> BuildDockerArgsForContext(string context, IReadOnlyList<string> args)
        => string.Equals(context, "default", StringComparison.Ordinal)
            ? [.. args]
            : PrependContextIfNeeded(context, args);

    internal static List<string> PrependContextIfNeeded(string? context, IReadOnlyList<string> args)
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
