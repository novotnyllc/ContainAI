using ContainAI.Cli.Host.DockerProxy.Contracts;

namespace ContainAI.Cli.Host.DockerProxy.System;

internal sealed class DockerProxyVolumeCredentialValidator : IDockerProxyVolumeCredentialValidator
{
    private readonly IDockerProxyCommandExecutor commandExecutor;

    public DockerProxyVolumeCredentialValidator(IDockerProxyCommandExecutor commandExecutor)
        => this.commandExecutor = commandExecutor;

    public async Task<bool> ValidateAsync(
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

        var marker = await commandExecutor.RunCaptureAsync(
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
