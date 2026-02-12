using ContainAI.Cli.Abstractions;
using ContainAI.Cli.Host.Devcontainer;

namespace ContainAI.Cli.Host.ContainerRuntime.Handlers;

internal sealed class ContainerRuntimeDevcontainerCommandHandler : IContainerRuntimeDevcontainerCommandHandler
{
    private readonly DevcontainerFeatureRuntime devcontainerRuntime;

    public ContainerRuntimeDevcontainerCommandHandler(DevcontainerFeatureRuntime devcontainerRuntime)
        => this.devcontainerRuntime = devcontainerRuntime ?? throw new ArgumentNullException(nameof(devcontainerRuntime));

    public Task<int> InstallAsync(SystemDevcontainerInstallCommandOptions options, CancellationToken cancellationToken)
        => devcontainerRuntime.RunInstallAsync(options, cancellationToken);

    public Task<int> InitAsync(CancellationToken cancellationToken)
        => devcontainerRuntime.RunInitAsync(cancellationToken);

    public Task<int> StartAsync(CancellationToken cancellationToken)
        => devcontainerRuntime.RunStartAsync(cancellationToken);

    public Task<int> VerifySysboxAsync(CancellationToken cancellationToken)
        => devcontainerRuntime.RunVerifySysboxAsync(cancellationToken);
}
