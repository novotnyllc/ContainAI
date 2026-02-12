using ContainAI.Cli.Host.ContainerRuntime.Configuration;
using ContainAI.Cli.Host.ContainerRuntime.Infrastructure;
using ContainAI.Cli.Host.ContainerRuntime.Models;

namespace ContainAI.Cli.Host.ContainerRuntime.Handlers;

internal sealed class ContainerRuntimeWatchLinksCommandHandler : IContainerRuntimeWatchLinksCommandHandler
{
    private readonly IContainerRuntimeExecutionContext context;
    private readonly IContainerRuntimeWatchLinksPollCycleProcessor pollCycleProcessor;

    public ContainerRuntimeWatchLinksCommandHandler(
        IContainerRuntimeExecutionContext context,
        IContainerRuntimeLinkRepairCommandHandler linkRepairCommandHandler)
        : this(
            context,
            new ContainerRuntimeWatchLinksPollCycleProcessor(
                context,
                new ContainerRuntimeWatchLinksRepairRunner(context, linkRepairCommandHandler)))
    {
    }

    internal ContainerRuntimeWatchLinksCommandHandler(
        IContainerRuntimeExecutionContext context,
        IContainerRuntimeWatchLinksPollCycleProcessor pollCycleProcessor)
    {
        this.context = context ?? throw new ArgumentNullException(nameof(context));
        this.pollCycleProcessor = pollCycleProcessor ?? throw new ArgumentNullException(nameof(pollCycleProcessor));
    }

    public async Task<int> HandleAsync(WatchLinksCommandParsing options, CancellationToken cancellationToken)
    {
        if (!await ValidateOptionsAsync(options).ConfigureAwait(false))
        {
            return 1;
        }

        await LogWatcherStartupAsync(options).ConfigureAwait(false);
        return await RunWatchLoopAsync(options, cancellationToken).ConfigureAwait(false);
    }

    private async Task<bool> ValidateOptionsAsync(WatchLinksCommandParsing options)
    {
        if (options.IsValid)
        {
            return true;
        }

        await context.StandardError.WriteLineAsync(options.ErrorMessage).ConfigureAwait(false);
        return false;
    }

    private async Task LogWatcherStartupAsync(WatchLinksCommandParsing options)
    {
        await context.LogInfoAsync(options.Quiet, $"Link watcher started (poll interval: {options.PollIntervalSeconds}s)").ConfigureAwait(false);
        await context.LogInfoAsync(options.Quiet, $"Watching: {options.ImportedAtPath} vs {options.CheckedAtPath}").ConfigureAwait(false);
    }

    private async Task<int> RunWatchLoopAsync(WatchLinksCommandParsing options, CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            if (!await WaitForPollIntervalAsync(options.PollIntervalSeconds, cancellationToken).ConfigureAwait(false))
            {
                break;
            }

            await pollCycleProcessor.ProcessCycleAsync(options, cancellationToken).ConfigureAwait(false);
        }

        return 0;
    }

    private static async Task<bool> WaitForPollIntervalAsync(int pollIntervalSeconds, CancellationToken cancellationToken)
    {
        try
        {
            await Task.Delay(TimeSpan.FromSeconds(pollIntervalSeconds), cancellationToken).ConfigureAwait(false);
            return true;
        }
        catch (OperationCanceledException)
        {
            return false;
        }
    }

}
