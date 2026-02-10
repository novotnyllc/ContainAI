using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed partial class ContainerRuntimeCommandService
{
    public Task<int> RunSystemInitAsync(SystemInitCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return initCommandHandler.HandleAsync(optionParser.ParseInitCommandOptions(options), cancellationToken);
    }

    public Task<int> RunSystemLinkRepairAsync(SystemLinkRepairCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return linkRepairCommandHandler.HandleAsync(optionParser.ParseLinkRepairCommandOptions(options), cancellationToken);
    }

    public Task<int> RunSystemWatchLinksAsync(SystemWatchLinksCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return watchLinksCommandHandler.HandleAsync(optionParser.ParseWatchLinksCommandOptions(options), cancellationToken);
    }

    public Task<int> RunSystemDevcontainerInstallAsync(SystemDevcontainerInstallCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return devcontainerCommandHandler.InstallAsync(options, cancellationToken);
    }

    public Task<int> RunSystemDevcontainerInitAsync(CancellationToken cancellationToken)
        => devcontainerCommandHandler.InitAsync(cancellationToken);

    public Task<int> RunSystemDevcontainerStartAsync(CancellationToken cancellationToken)
        => devcontainerCommandHandler.StartAsync(cancellationToken);

    public Task<int> RunSystemDevcontainerVerifySysboxAsync(CancellationToken cancellationToken)
        => devcontainerCommandHandler.VerifySysboxAsync(cancellationToken);
}
