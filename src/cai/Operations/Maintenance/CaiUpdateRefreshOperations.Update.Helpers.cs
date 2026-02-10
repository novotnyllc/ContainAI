namespace ContainAI.Cli.Host;

internal sealed partial class CaiUpdateRefreshOperations
{
    private async Task<int> WriteUpdateUsageAsync()
    {
        await stdout.WriteLineAsync("Usage: cai update [--dry-run] [--stop-containers] [--force] [--lima-recreate]").ConfigureAwait(false);
        return 0;
    }

    private async Task<int> RunUpdateDryRunAsync(bool stopContainers, bool limaRecreate)
    {
        await stdout.WriteLineAsync("Would pull latest base image for configured channel.").ConfigureAwait(false);
        if (stopContainers)
        {
            await stdout.WriteLineAsync("Would stop running ContainAI containers before update.").ConfigureAwait(false);
        }

        if (limaRecreate)
        {
            await stdout.WriteLineAsync("Would recreate Lima VM 'containai'.").ConfigureAwait(false);
        }

        await stdout.WriteLineAsync("Would refresh templates and verify installation.").ConfigureAwait(false);
        return 0;
    }

    private async Task<int> RecreateLimaVmAsync(CancellationToken cancellationToken)
    {
        await stdout.WriteLineAsync("Recreating Lima VM 'containai'...").ConfigureAwait(false);
        await RunProcessCaptureAsync("limactl", ["delete", "containai", "--force"], cancellationToken).ConfigureAwait(false);
        var start = await RunProcessCaptureAsync("limactl", ["start", "containai"], cancellationToken).ConfigureAwait(false);
        if (start.ExitCode != 0)
        {
            await stderr.WriteLineAsync(start.StandardError.Trim()).ConfigureAwait(false);
            return 1;
        }

        return 0;
    }

    private static async Task StopManagedContainersAsync(CancellationToken cancellationToken)
    {
        var stopResult = await DockerCaptureAsync(
            ["ps", "-q", "--filter", "label=containai.managed=true"],
            cancellationToken).ConfigureAwait(false);

        if (stopResult.ExitCode != 0)
        {
            return;
        }

        foreach (var containerId in stopResult.StandardOutput.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            await DockerCaptureAsync(["stop", containerId], cancellationToken).ConfigureAwait(false);
        }
    }
}
