namespace ContainAI.Cli.Host;

internal sealed partial class CaiUninstallOperations
{
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
}
