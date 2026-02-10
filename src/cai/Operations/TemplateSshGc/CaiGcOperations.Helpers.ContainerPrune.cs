namespace ContainAI.Cli.Host;

internal sealed partial class CaiGcOperations
{
    private async Task<bool> ConfirmContainerPruneAsync(bool dryRun, bool force, int candidateCount)
    {
        if (dryRun || force || candidateCount == 0)
        {
            return true;
        }

        if (Console.IsInputRedirected)
        {
            await stderr.WriteLineAsync("gc requires --force in non-interactive mode.").ConfigureAwait(false);
            return false;
        }

        await stdout.WriteLineAsync($"About to remove {candidateCount} containers. Continue? [y/N]").ConfigureAwait(false);
        var response = (Console.ReadLine() ?? string.Empty).Trim();
        if (!response.Equals("y", StringComparison.OrdinalIgnoreCase) &&
            !response.Equals("yes", StringComparison.OrdinalIgnoreCase))
        {
            await stdout.WriteLineAsync("Aborted.").ConfigureAwait(false);
            return false;
        }

        return true;
    }

    private async Task<int> PruneContainersAsync(IReadOnlyList<string> pruneCandidates, bool dryRun, CancellationToken cancellationToken)
    {
        var failures = 0;
        foreach (var containerId in pruneCandidates)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (dryRun)
            {
                await stdout.WriteLineAsync($"Would remove container {containerId}").ConfigureAwait(false);
                continue;
            }

            var removeResult = await DockerRunAsync(["rm", "-f", containerId], cancellationToken).ConfigureAwait(false);
            if (removeResult != 0)
            {
                failures++;
            }
        }

        return failures;
    }
}
