namespace ContainAI.Cli.Host;

internal sealed partial class CaiUninstallOperations
{
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
