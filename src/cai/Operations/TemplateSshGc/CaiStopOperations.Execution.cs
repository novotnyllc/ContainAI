namespace ContainAI.Cli.Host;

internal sealed partial class CaiStopOperations
{
    private async Task<int> StopTargetsAsync(
        IReadOnlyList<(string Context, string Container)> targets,
        bool remove,
        bool force,
        bool exportFirst,
        CancellationToken cancellationToken)
    {
        var failures = 0;
        foreach (var target in targets)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (exportFirst)
            {
                var exportExitCode = await runExportAsync(null, null, target.Container, null, cancellationToken).ConfigureAwait(false);
                if (exportExitCode != 0)
                {
                    failures++;
                    await stderr.WriteLineAsync($"Failed to export data volume for container: {target.Container}").ConfigureAwait(false);
                    if (!force)
                    {
                        continue;
                    }
                }
            }

            var stopResult = await DockerCaptureForContextAsync(target.Context, ["stop", target.Container], cancellationToken).ConfigureAwait(false);
            if (stopResult.ExitCode != 0)
            {
                failures++;
                await stderr.WriteLineAsync($"Failed to stop container: {target.Container}").ConfigureAwait(false);
                if (!force)
                {
                    continue;
                }
            }

            if (remove)
            {
                var removeResult = await DockerCaptureForContextAsync(target.Context, ["rm", "-f", target.Container], cancellationToken).ConfigureAwait(false);
                if (removeResult.ExitCode != 0)
                {
                    failures++;
                    await stderr.WriteLineAsync($"Failed to remove container: {target.Container}").ConfigureAwait(false);
                }
            }
        }

        return failures;
    }
}
