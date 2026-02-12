using ContainAI.Cli.Host.RuntimeSupport.Docker;

namespace ContainAI.Cli.Host;

internal sealed class CaiUninstallContainerAndVolumeCleaner : ICaiUninstallContainerAndVolumeCleaner
{
    private readonly TextWriter stdout;
    private readonly TextWriter stderr;

    public CaiUninstallContainerAndVolumeCleaner(TextWriter standardOutput, TextWriter standardError)
    {
        stdout = standardOutput ?? throw new ArgumentNullException(nameof(standardOutput));
        stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));
    }

    public async Task<CaiUninstallContainerCleanupResult> RemoveManagedContainersAndCollectVolumesAsync(
        bool dryRun,
        bool removeVolumes,
        CancellationToken cancellationToken)
    {
        var list = await CaiRuntimeDockerHelpers
            .DockerCaptureAsync(["ps", "-aq", "--filter", "label=containai.managed=true"], cancellationToken)
            .ConfigureAwait(false);

        if (list.ExitCode != 0)
        {
            await stderr.WriteLineAsync(list.StandardError.Trim()).ConfigureAwait(false);
            return new CaiUninstallContainerCleanupResult(1, []);
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
                await CaiRuntimeDockerHelpers.DockerCaptureAsync(["rm", "-f", containerId], cancellationToken).ConfigureAwait(false);
            }

            if (!removeVolumes)
            {
                continue;
            }

            var inspect = await CaiRuntimeDockerHelpers
                .DockerCaptureAsync(
                    ["inspect", "--format", "{{range .Mounts}}{{if and (eq .Type \"volume\") (eq .Destination \"/mnt/agent-data\")}}{{.Name}}{{end}}{{end}}", containerId],
                    cancellationToken)
                .ConfigureAwait(false);

            if (inspect.ExitCode == 0)
            {
                var volumeName = inspect.StandardOutput.Trim();
                if (!string.IsNullOrWhiteSpace(volumeName))
                {
                    volumeNames.Add(volumeName);
                }
            }
        }

        return new CaiUninstallContainerCleanupResult(0, volumeNames);
    }

    public async Task RemoveVolumesAsync(IReadOnlyCollection<string> volumeNames, bool dryRun, CancellationToken cancellationToken)
    {
        foreach (var volume in volumeNames)
        {
            if (dryRun)
            {
                await stdout.WriteLineAsync($"Would remove volume {volume}").ConfigureAwait(false);
                continue;
            }

            await CaiRuntimeDockerHelpers.DockerCaptureAsync(["volume", "rm", volume], cancellationToken).ConfigureAwait(false);
        }
    }
}
