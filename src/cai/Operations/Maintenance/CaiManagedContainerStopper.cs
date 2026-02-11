using ContainAI.Cli.Host.RuntimeSupport.Docker;

namespace ContainAI.Cli.Host;

internal interface ICaiManagedContainerStopper
{
    Task StopAsync(CancellationToken cancellationToken);
}

internal sealed class CaiManagedContainerStopper : ICaiManagedContainerStopper
{
    public async Task StopAsync(CancellationToken cancellationToken)
    {
        var stopResult = await CaiRuntimeDockerHelpers.DockerCaptureAsync(
            ["ps", "-q", "--filter", "label=containai.managed=true"],
            cancellationToken).ConfigureAwait(false);

        if (stopResult.ExitCode != 0)
        {
            return;
        }

        foreach (var containerId in stopResult.StandardOutput.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            await CaiRuntimeDockerHelpers.DockerCaptureAsync(["stop", containerId], cancellationToken).ConfigureAwait(false);
        }
    }
}
