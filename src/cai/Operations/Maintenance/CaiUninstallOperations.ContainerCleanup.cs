namespace ContainAI.Cli.Host;

internal sealed partial class CaiUninstallOperations
{
    private readonly record struct UninstallContainerRemovalResult(int ExitCode, HashSet<string> VolumeNames);

    private async Task RemoveDockerContextsAsync(bool dryRun, CancellationToken cancellationToken)
    {
        var contextsToRemove = new[] { "containai-docker", "containai-secure", "docker-containai" };
        foreach (var context in contextsToRemove)
        {
            if (dryRun)
            {
                await stdout.WriteLineAsync($"Would remove Docker context: {context}").ConfigureAwait(false);
                continue;
            }

            await DockerCaptureAsync(["context", "rm", "-f", context], cancellationToken).ConfigureAwait(false);
        }
    }

    private async Task<UninstallContainerRemovalResult> RemoveManagedContainersAndCollectVolumesAsync(
        bool dryRun,
        bool removeVolumes,
        CancellationToken cancellationToken)
    {
        var list = await DockerCaptureAsync(["ps", "-aq", "--filter", "label=containai.managed=true"], cancellationToken).ConfigureAwait(false);
        if (list.ExitCode != 0)
        {
            await stderr.WriteLineAsync(list.StandardError.Trim()).ConfigureAwait(false);
            return new UninstallContainerRemovalResult(1, []);
        }

        var containerIds = list.StandardOutput.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        var volumeNames = new HashSet<string>(StringComparer.Ordinal);
        foreach (var containerId in containerIds)
        {
            if (dryRun)
            {
                await stdout.WriteLineAsync($"Would remove container {containerId}").ConfigureAwait(false);
            }
            else
            {
                await DockerCaptureAsync(["rm", "-f", containerId], cancellationToken).ConfigureAwait(false);
            }

            if (!removeVolumes)
            {
                continue;
            }

            var inspect = await DockerCaptureAsync(
                ["inspect", "--format", "{{range .Mounts}}{{if and (eq .Type \"volume\") (eq .Destination \"/mnt/agent-data\")}}{{.Name}}{{end}}{{end}}", containerId],
                cancellationToken).ConfigureAwait(false);
            if (inspect.ExitCode == 0)
            {
                var volumeName = inspect.StandardOutput.Trim();
                if (!string.IsNullOrWhiteSpace(volumeName))
                {
                    volumeNames.Add(volumeName);
                }
            }
        }

        return new UninstallContainerRemovalResult(0, volumeNames);
    }

    private async Task RemoveVolumesAsync(IReadOnlyCollection<string> volumeNames, bool dryRun, CancellationToken cancellationToken)
    {
        foreach (var volume in volumeNames)
        {
            if (dryRun)
            {
                await stdout.WriteLineAsync($"Would remove volume {volume}").ConfigureAwait(false);
                continue;
            }

            await DockerCaptureAsync(["volume", "rm", volume], cancellationToken).ConfigureAwait(false);
        }
    }
}
