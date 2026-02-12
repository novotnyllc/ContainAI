using ContainAI.Cli.Host.RuntimeSupport.Docker;

namespace ContainAI.Cli.Host.Importing.Transfer;

internal sealed class ImportManifestTargetEnsureExecutor(TextWriter standardError) : IImportManifestTargetEnsureExecutor
{
    public async Task<int> EnsureAsync(string volume, string command, CancellationToken cancellationToken)
    {
        var ensureResult = await CaiRuntimeDockerHelpers.DockerCaptureAsync(
            ["run", "--rm", "-v", $"{volume}:/mnt/agent-data", "alpine:3.20", "sh", "-lc", command],
            cancellationToken).ConfigureAwait(false);
        if (ensureResult.ExitCode == 0)
        {
            return 0;
        }

        await standardError.WriteLineAsync(ensureResult.StandardError.Trim()).ConfigureAwait(false);
        return 1;
    }
}
