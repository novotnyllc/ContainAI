using ContainAI.Cli.Host.RuntimeSupport.Docker;

namespace ContainAI.Cli.Host;

internal sealed class CaiGcContainerPruner : ICaiGcContainerPruner
{
    private readonly TextWriter stdout;

    public CaiGcContainerPruner(TextWriter standardOutput)
        => stdout = standardOutput ?? throw new ArgumentNullException(nameof(standardOutput));

    public async Task<int> PruneAsync(
        IReadOnlyList<string> pruneCandidates,
        bool dryRun,
        CancellationToken cancellationToken)
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

            var removeResult = await CaiRuntimeDockerHelpers.DockerRunAsync(["rm", "-f", containerId], cancellationToken).ConfigureAwait(false);
            if (removeResult != 0)
            {
                failures++;
            }
        }

        return failures;
    }
}
