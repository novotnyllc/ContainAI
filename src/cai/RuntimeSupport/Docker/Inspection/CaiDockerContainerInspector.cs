using ContainAI.Cli.Host.RuntimeSupport.Docker.Execution;

namespace ContainAI.Cli.Host.RuntimeSupport.Docker.Inspection;

internal static class CaiDockerContainerInspector
{
    public static async Task<bool> DockerContainerExistsAsync(string containerName, CancellationToken cancellationToken)
    {
        var result = await CaiDockerCommandRunner
            .DockerRunAsync(["inspect", "--type", "container", containerName], cancellationToken)
            .ConfigureAwait(false);
        return result == 0;
    }

    public static async Task<string?> ResolveDataVolumeFromContainerAsync(
        string containerName,
        string? explicitVolume,
        CancellationToken cancellationToken)
    {
        if (!string.IsNullOrWhiteSpace(explicitVolume))
        {
            return explicitVolume;
        }

        var inspect = await CaiDockerCommandRunner
            .DockerCaptureAsync(
                ["inspect", "--format", "{{range .Mounts}}{{if and (eq .Type \"volume\") (eq .Destination \"/mnt/agent-data\")}}{{.Name}}{{end}}{{end}}", containerName],
                cancellationToken)
            .ConfigureAwait(false);

        if (inspect.ExitCode != 0)
        {
            return null;
        }

        var volumeName = inspect.StandardOutput.Trim();
        return string.IsNullOrWhiteSpace(volumeName) ? null : volumeName;
    }
}
