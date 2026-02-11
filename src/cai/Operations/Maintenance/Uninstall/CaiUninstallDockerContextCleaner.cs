using ContainAI.Cli.Host.RuntimeSupport.Docker;

namespace ContainAI.Cli.Host;

internal interface ICaiUninstallDockerContextCleaner
{
    Task CleanAsync(bool dryRun, CancellationToken cancellationToken);
}

internal sealed class CaiUninstallDockerContextCleaner : ICaiUninstallDockerContextCleaner
{
    private static readonly string[] ContextsToRemove =
    [
        "containai-docker",
        "containai-secure",
        "docker-containai",
    ];

    private readonly TextWriter stdout;

    public CaiUninstallDockerContextCleaner(TextWriter standardOutput)
        => stdout = standardOutput ?? throw new ArgumentNullException(nameof(standardOutput));

    public async Task CleanAsync(bool dryRun, CancellationToken cancellationToken)
    {
        foreach (var context in ContextsToRemove)
        {
            if (dryRun)
            {
                await stdout.WriteLineAsync($"Would remove Docker context: {context}").ConfigureAwait(false);
                continue;
            }

            await CaiRuntimeDockerHelpers.DockerCaptureAsync(["context", "rm", "-f", context], cancellationToken).ConfigureAwait(false);
        }
    }
}
