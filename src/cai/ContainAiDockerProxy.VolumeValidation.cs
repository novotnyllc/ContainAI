namespace ContainAI.Cli.Host;

internal sealed partial class ContainAiDockerProxyService
{
    private async Task<bool> ValidateVolumeCredentialsAsync(
        string contextName,
        string dataVolume,
        bool enableCredentials,
        bool quiet,
        TextWriter stderr,
        CancellationToken cancellationToken)
    {
        if (enableCredentials)
        {
            return true;
        }

        var marker = await RunDockerCaptureAsync(
            ["--context", contextName, "run", "--rm", "-v", $"{dataVolume}:/vol:ro", "alpine", "test", "-f", "/vol/.containai-no-secrets"],
            cancellationToken).ConfigureAwait(false);

        if (marker.ExitCode == 0)
        {
            return true;
        }

        if (!quiet)
        {
            await stderr.WriteLineAsync($"[cai-docker] Warning: volume {dataVolume} may contain credentials").ConfigureAwait(false);
            await stderr.WriteLineAsync("[cai-docker] Warning: set enableCredentials=true for trusted repositories").ConfigureAwait(false);
        }

        return false;
    }
}
