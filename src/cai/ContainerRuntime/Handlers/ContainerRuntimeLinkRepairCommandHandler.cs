using ContainAI.Cli.Host.ContainerRuntime.Configuration;
using ContainAI.Cli.Host.ContainerRuntime.Infrastructure;
using ContainAI.Cli.Host.ContainerRuntime.Models;
using ContainAI.Cli.Host;

namespace ContainAI.Cli.Host.ContainerRuntime.Handlers;

internal sealed class ContainerRuntimeLinkRepairCommandHandler : IContainerRuntimeLinkRepairCommandHandler
{
    private readonly IContainerRuntimeExecutionContext context;
    private readonly IContainerRuntimeLinkSpecProcessor linkSpecProcessor;

    public ContainerRuntimeLinkRepairCommandHandler(
        IContainerRuntimeExecutionContext context,
        IContainerRuntimeLinkSpecProcessor linkSpecProcessor)
    {
        this.context = context ?? throw new ArgumentNullException(nameof(context));
        this.linkSpecProcessor = linkSpecProcessor ?? throw new ArgumentNullException(nameof(linkSpecProcessor));
    }

    public async Task<int> HandleAsync(LinkRepairCommandParsing options, CancellationToken cancellationToken)
    {
        if (!File.Exists(options.BuiltinSpecPath))
        {
            await context.StandardError.WriteLineAsync($"ERROR: Built-in link spec not found: {options.BuiltinSpecPath}").ConfigureAwait(false);
            return 1;
        }

        var stats = new LinkRepairStats();
        try
        {
            await linkSpecProcessor.ProcessLinkSpecAsync(options.BuiltinSpecPath, options.Mode, options.Quiet, "built-in links", stats, cancellationToken).ConfigureAwait(false);
            if (File.Exists(options.UserSpecPath))
            {
                try
                {
                    await linkSpecProcessor.ProcessLinkSpecAsync(options.UserSpecPath, options.Mode, options.Quiet, "user-defined links", stats, cancellationToken).ConfigureAwait(false);
                }
                catch (Exception ex) when (ContainerRuntimeExceptionHandling.IsHandled(ex))
                {
                    await WriteUserLinkSpecWarningAsync(stats, ex).ConfigureAwait(false);
                }
            }

            if (options.Mode == LinkRepairMode.Fix && stats.Errors == 0)
            {
                await context.WriteTimestampAsync(options.CheckedAtFilePath).ConfigureAwait(false);
                await context.LogInfoAsync(options.Quiet, "Updated links-checked-at timestamp").ConfigureAwait(false);
            }

            await linkSpecProcessor.WriteSummaryAsync(options.Mode, stats, options.Quiet).ConfigureAwait(false);
            if (stats.Errors > 0)
            {
                return 1;
            }

            if (options.Mode == LinkRepairMode.Check && (stats.Broken + stats.Missing) > 0)
            {
                return 1;
            }

            return 0;
        }
        catch (Exception ex) when (ContainerRuntimeExceptionHandling.IsHandled(ex))
        {
            await context.StandardError.WriteLineAsync($"ERROR: {ex.Message}").ConfigureAwait(false);
            return 1;
        }
    }

    private async Task WriteUserLinkSpecWarningAsync(LinkRepairStats stats, Exception exception)
    {
        stats.Errors++;
        await context.StandardError.WriteLineAsync($"[WARN] Failed to process user link spec: {exception.Message}").ConfigureAwait(false);
    }
}
