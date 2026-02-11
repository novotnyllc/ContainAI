using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed class CaiRuntimeSystemCommandHandler
{
    private readonly CaiOperationsService operationsService;

    public CaiRuntimeSystemCommandHandler(CaiOperationsService service)
        => operationsService = service ?? throw new ArgumentNullException(nameof(service));

    public Task<int> RunSystemInitAsync(SystemInitCommandOptions options, CancellationToken cancellationToken)
        => operationsService.RunSystemInitAsync(options, cancellationToken);

    public Task<int> RunSystemLinkRepairAsync(SystemLinkRepairCommandOptions options, CancellationToken cancellationToken)
        => operationsService.RunSystemLinkRepairAsync(options, cancellationToken);

    public Task<int> RunSystemWatchLinksAsync(SystemWatchLinksCommandOptions options, CancellationToken cancellationToken)
        => operationsService.RunSystemWatchLinksAsync(options, cancellationToken);

    public Task<int> RunSystemDevcontainerInstallAsync(SystemDevcontainerInstallCommandOptions options, CancellationToken cancellationToken)
        => operationsService.RunSystemDevcontainerInstallAsync(options, cancellationToken);

    public Task<int> RunSystemDevcontainerInitAsync(CancellationToken cancellationToken)
        => operationsService.RunSystemDevcontainerInitAsync(cancellationToken);

    public Task<int> RunSystemDevcontainerStartAsync(CancellationToken cancellationToken)
        => operationsService.RunSystemDevcontainerStartAsync(cancellationToken);

    public Task<int> RunSystemDevcontainerVerifySysboxAsync(CancellationToken cancellationToken)
        => operationsService.RunSystemDevcontainerVerifySysboxAsync(cancellationToken);
}
