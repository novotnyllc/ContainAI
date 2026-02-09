namespace ContainAI.Cli.Host;

internal sealed partial class CaiOperationsService : CaiRuntimeSupport
{
    private async Task<int> RunSshCleanupCoreAsync(bool dryRun, CancellationToken cancellationToken)
    {
        var sshDir = Path.Combine(ResolveHomeDirectory(), ".ssh", "containai.d");
        if (!Directory.Exists(sshDir))
        {
            return 0;
        }

        var removed = 0;
        foreach (var file in Directory.EnumerateFiles(sshDir, "*.conf"))
        {
            cancellationToken.ThrowIfCancellationRequested();
            var containerName = Path.GetFileNameWithoutExtension(file);
            var exists = await DockerContainerExistsAsync(containerName, cancellationToken).ConfigureAwait(false);
            if (exists)
            {
                continue;
            }

            removed++;
            if (dryRun)
            {
                await stdout.WriteLineAsync($"Would remove {file}").ConfigureAwait(false);
                continue;
            }

            File.Delete(file);
            await stdout.WriteLineAsync($"Removed {file}").ConfigureAwait(false);
        }

        if (removed == 0)
        {
            await stdout.WriteLineAsync("No stale SSH configs found.").ConfigureAwait(false);
        }

        return 0;
    }
}
