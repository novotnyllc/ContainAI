namespace ContainAI.Cli.Host;

internal static partial class SessionRuntimeDockerHelpers
{
    internal static async Task<bool> DockerContextExistsAsync(string context, CancellationToken cancellationToken)
    {
        if (string.Equals(context, "default", StringComparison.Ordinal))
        {
            return true;
        }

        var inspect = await SessionRuntimeProcessHelpers
            .RunProcessCaptureAsync("docker", ["context", "inspect", context], cancellationToken)
            .ConfigureAwait(false);
        return inspect.ExitCode == 0;
    }

    internal static async Task<ProcessResult> DockerCaptureAsync(
        string context,
        IReadOnlyList<string> dockerArgs,
        CancellationToken cancellationToken)
    {
        var args = new List<string>();
        if (!string.IsNullOrWhiteSpace(context) && !string.Equals(context, "default", StringComparison.Ordinal))
        {
            args.Add("--context");
            args.Add(context);
        }

        args.AddRange(dockerArgs);
        return await SessionRuntimeProcessHelpers.RunProcessCaptureAsync("docker", args, cancellationToken).ConfigureAwait(false);
    }
}
