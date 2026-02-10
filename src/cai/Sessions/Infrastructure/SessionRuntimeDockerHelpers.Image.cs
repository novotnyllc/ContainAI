namespace ContainAI.Cli.Host;

internal static partial class SessionRuntimeDockerHelpers
{
    internal static bool IsContainAiImage(string image)
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

    internal static string ResolveImage(SessionCommandOptions options)
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
