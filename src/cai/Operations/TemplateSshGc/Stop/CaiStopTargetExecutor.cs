using ContainAI.Cli.Host.RuntimeSupport.Docker;

namespace ContainAI.Cli.Host;

internal sealed class CaiStopTargetExecutor : ICaiStopTargetExecutor
{
    private readonly TextWriter stderr;
    private readonly Func<string?, string?, string?, string?, CancellationToken, Task<int>> runExportAsync;

    public CaiStopTargetExecutor(
        TextWriter standardError,
        Func<string?, string?, string?, string?, CancellationToken, Task<int>> runExportAsync)
    {
        stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));
        this.runExportAsync = runExportAsync ?? throw new ArgumentNullException(nameof(runExportAsync));
    }

    public async Task<int> ExecuteAsync(
        IReadOnlyList<CaiStopTarget> targets,
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

            var stopResult = await CaiRuntimeDockerHelpers
                .DockerCaptureForContextAsync(target.Context, ["stop", target.Container], cancellationToken)
                .ConfigureAwait(false);
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
                var removeResult = await CaiRuntimeDockerHelpers
                    .DockerCaptureForContextAsync(target.Context, ["rm", "-f", target.Container], cancellationToken)
                    .ConfigureAwait(false);
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
