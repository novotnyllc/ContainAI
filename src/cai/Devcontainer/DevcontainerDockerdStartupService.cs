namespace ContainAI.Cli.Host.Devcontainer;

internal interface IDevcontainerDockerdStartupService
{
    Task<int> StartDockerdAsync(CancellationToken cancellationToken);
}

internal sealed class DevcontainerDockerdStartupService(
    IDevcontainerProcessHelpers processHelpers,
    TextWriter standardOutput,
    TextWriter standardError) : IDevcontainerDockerdStartupService
{
    public async Task<int> StartDockerdAsync(CancellationToken cancellationToken)
    {
        if (!await processHelpers.CommandExistsAsync("dockerd", cancellationToken).ConfigureAwait(false))
        {
            return 0;
        }

        if (File.Exists(DevcontainerFeaturePaths.DefaultDockerPidFile))
        {
            var pidRaw = await File.ReadAllTextAsync(DevcontainerFeaturePaths.DefaultDockerPidFile, cancellationToken).ConfigureAwait(false);
            if (int.TryParse(pidRaw.Trim(), out var existingPid) && processHelpers.IsProcessAlive(existingPid))
            {
                await standardOutput.WriteLineAsync($"[OK] dockerd already running (pid {existingPid})").ConfigureAwait(false);
                return 0;
            }

            await processHelpers.RunAsRootAsync("rm", ["-f", DevcontainerFeaturePaths.DefaultDockerPidFile], cancellationToken).ConfigureAwait(false);
        }

        if (await processHelpers.CommandSucceedsAsync("docker", ["info"], cancellationToken).ConfigureAwait(false))
        {
            await standardOutput.WriteLineAsync("[OK] dockerd already running (socket active)").ConfigureAwait(false);
            return 0;
        }

        await standardOutput.WriteLineAsync("Starting dockerd...").ConfigureAwait(false);
        await processHelpers.RunAsRootAsync(
            "sh",
            ["-c", $"nohup dockerd --pidfile={DevcontainerFeaturePaths.DefaultDockerPidFile} > {DevcontainerFeaturePaths.DefaultDockerLogFile} 2>&1 &"],
            cancellationToken).ConfigureAwait(false);

        for (var attempt = 0; attempt < 30; attempt++)
        {
            if (await processHelpers.CommandSucceedsAsync("docker", ["info"], cancellationToken).ConfigureAwait(false))
            {
                await standardOutput.WriteLineAsync("[OK] dockerd started (DinD ready)").ConfigureAwait(false);
                return 0;
            }

            await Task.Delay(TimeSpan.FromSeconds(1), cancellationToken).ConfigureAwait(false);
        }

        await standardError.WriteLineAsync($"[FAIL] dockerd failed to start (see {DevcontainerFeaturePaths.DefaultDockerLogFile})").ConfigureAwait(false);
        return 1;
    }
}
