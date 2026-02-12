using ContainAI.Cli.Host.DockerProxy.Contracts;
using ContainAI.Cli.Host.DockerProxy.Models;

namespace ContainAI.Cli.Host.DockerProxy.Execution;

internal sealed class DockerProxyProcessRunner : IDockerProxyProcessRunner
{
    public Task<int> RunInteractiveAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => CliWrapProcessRunner.RunInteractiveAsync("docker", args, cancellationToken);

    public async Task<DockerProxyProcessResult> RunCaptureAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        var result = await CliWrapProcessRunner.RunCaptureAsync("docker", args, cancellationToken).ConfigureAwait(false);
        return new DockerProxyProcessResult(result.ExitCode, result.StandardOutput, result.StandardError);
    }
}
