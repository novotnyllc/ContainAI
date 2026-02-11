using ContainAI.Cli.Host.RuntimeSupport.Docker;
using ContainAI.Cli.Host.RuntimeSupport.Models;

namespace ContainAI.Cli.Host;

internal interface ICaiDockerImagePuller
{
    Task<RuntimeProcessResult> PullAsync(string imageName, CancellationToken cancellationToken);
}

internal sealed class CaiDockerImagePuller : ICaiDockerImagePuller
{
    public Task<RuntimeProcessResult> PullAsync(string imageName, CancellationToken cancellationToken)
        => CaiRuntimeDockerHelpers.DockerCaptureAsync(["pull", imageName], cancellationToken);
}
