namespace ContainAI.Cli.Host;

internal static partial class SessionRuntimeInfrastructure
{
    public static Task<bool> DockerContextExistsAsync(string context, CancellationToken cancellationToken)
        => SessionRuntimeDockerHelpers.DockerContextExistsAsync(context, cancellationToken);

    public static Task<ProcessResult> DockerCaptureAsync(
        string context,
        IReadOnlyList<string> dockerArgs,
        CancellationToken cancellationToken)
        => SessionRuntimeDockerHelpers.DockerCaptureAsync(context, dockerArgs, cancellationToken);

    public static bool IsContainAiImage(string image) => SessionRuntimeDockerHelpers.IsContainAiImage(image);

    public static bool IsValidVolumeName(string name) => SessionRuntimeDockerHelpers.IsValidVolumeName(name);

    public static string ResolveImage(SessionCommandOptions options) => SessionRuntimeDockerHelpers.ResolveImage(options);
}
