namespace ContainAI.Cli.Host;

internal static partial class SessionRuntimeInfrastructure
{
    public static async Task<bool> DockerContextExistsAsync(string context, CancellationToken cancellationToken)
    {
        if (string.Equals(context, "default", StringComparison.Ordinal))
        {
            return true;
        }

        var inspect = await RunProcessCaptureAsync("docker", ["context", "inspect", context], cancellationToken).ConfigureAwait(false);
        return inspect.ExitCode == 0;
    }

    public static async Task<ProcessResult> DockerCaptureAsync(string context, IReadOnlyList<string> dockerArgs, CancellationToken cancellationToken)
    {
        var args = new List<string>();
        if (!string.IsNullOrWhiteSpace(context) && !string.Equals(context, "default", StringComparison.Ordinal))
        {
            args.Add("--context");
            args.Add(context);
        }

        args.AddRange(dockerArgs);
        return await RunProcessCaptureAsync("docker", args, cancellationToken).ConfigureAwait(false);
    }

    public static bool IsContainAiImage(string image)
    {
        if (string.IsNullOrWhiteSpace(image))
        {
            return false;
        }

        foreach (var prefix in SessionRuntimeConstants.ContainAiImagePrefixes)
        {
            if (image.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }

        return false;
    }

    public static bool IsValidVolumeName(string name)
    {
        if (string.IsNullOrWhiteSpace(name) || name.Length > 255)
        {
            return false;
        }

        if (!char.IsLetterOrDigit(name[0]))
        {
            return false;
        }

        foreach (var ch in name)
        {
            if (!(char.IsLetterOrDigit(ch) || ch is '_' or '.' or '-'))
            {
                return false;
            }
        }

        return true;
    }

    public static string ResolveImage(SessionCommandOptions options)
    {
        if (!string.IsNullOrWhiteSpace(options.ImageTag) && string.IsNullOrWhiteSpace(options.Template))
        {
            return $"{SessionRuntimeConstants.ContainAiRepo}:{options.ImageTag}";
        }

        if (string.Equals(options.Channel, "nightly", StringComparison.OrdinalIgnoreCase))
        {
            return $"{SessionRuntimeConstants.ContainAiRepo}:nightly";
        }

        return $"{SessionRuntimeConstants.ContainAiRepo}:{SessionRuntimeConstants.DefaultImageTag}";
    }
}
