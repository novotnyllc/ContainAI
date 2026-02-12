using ContainAI.Cli.Abstractions;
using ContainAI.Cli.Host;
using ContainAI.Cli.Host.ContainerRuntime.Configuration;

namespace ContainAI.Cli.Host.ContainerRuntime.Handlers;

internal interface IContainerRuntimeInitCommandHandler
{
    Task<int> HandleAsync(InitCommandParsing options, CancellationToken cancellationToken);
}

internal interface IContainerRuntimeLinkRepairCommandHandler
{
    Task<int> HandleAsync(LinkRepairCommandParsing options, CancellationToken cancellationToken);
}

internal interface IContainerRuntimeWatchLinksCommandHandler
{
    Task<int> HandleAsync(WatchLinksCommandParsing options, CancellationToken cancellationToken);
}

internal interface IContainerRuntimeDevcontainerCommandHandler
{
    Task<int> InstallAsync(SystemDevcontainerInstallCommandOptions options, CancellationToken cancellationToken);

    Task<int> InitAsync(CancellationToken cancellationToken);

    Task<int> StartAsync(CancellationToken cancellationToken);

    Task<int> VerifySysboxAsync(CancellationToken cancellationToken);
}
