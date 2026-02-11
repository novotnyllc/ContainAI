using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed class CaiSystemCommandHandler
{
    private readonly ContainerRuntimeCommandService containerRuntimeCommandService;

    public CaiSystemCommandHandler(ContainerRuntimeCommandService runtimeCommandService)
        => containerRuntimeCommandService = runtimeCommandService ?? throw new ArgumentNullException(nameof(runtimeCommandService));

    public Task<int> RunSystemInitAsync(SystemInitCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return containerRuntimeCommandService.RunSystemInitAsync(options, cancellationToken);
    }

    public Task<int> RunSystemLinkRepairAsync(SystemLinkRepairCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return containerRuntimeCommandService.RunSystemLinkRepairAsync(options, cancellationToken);
    }

    public Task<int> RunSystemWatchLinksAsync(SystemWatchLinksCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return containerRuntimeCommandService.RunSystemWatchLinksAsync(options, cancellationToken);
    }

    public Task<int> RunSystemDevcontainerInstallAsync(SystemDevcontainerInstallCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return containerRuntimeCommandService.RunSystemDevcontainerInstallAsync(options, cancellationToken);
    }

    public Task<int> RunSystemDevcontainerInitAsync(CancellationToken cancellationToken)
        => containerRuntimeCommandService.RunSystemDevcontainerInitAsync(cancellationToken);

    public Task<int> RunSystemDevcontainerStartAsync(CancellationToken cancellationToken)
        => containerRuntimeCommandService.RunSystemDevcontainerStartAsync(cancellationToken);

    public Task<int> RunSystemDevcontainerVerifySysboxAsync(CancellationToken cancellationToken)
        => containerRuntimeCommandService.RunSystemDevcontainerVerifySysboxAsync(cancellationToken);
}
