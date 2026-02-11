using ContainAI.Cli.Host.ContainerRuntime.Configuration;
using ContainAI.Cli.Host.ContainerRuntime.Models;
using ContainAI.Cli.Host.ContainerRuntime.Infrastructure;

namespace ContainAI.Cli.Host.ContainerRuntime.Handlers;

internal interface IContainerRuntimeWatchLinksRepairRunner
{
    Task RunAsync(
        WatchLinksCommandParsing options,
        string importedTimestamp,
        string checkedTimestamp,
        CancellationToken cancellationToken);
}

internal sealed class ContainerRuntimeWatchLinksRepairRunner(
    IContainerRuntimeExecutionContext context,
    IContainerRuntimeLinkRepairCommandHandler linkRepairCommandHandler) : IContainerRuntimeWatchLinksRepairRunner
{
    public async Task RunAsync(
        WatchLinksCommandParsing options,
        string importedTimestamp,
        string checkedTimestamp,
        CancellationToken cancellationToken)
    {
        await context.LogInfoAsync(
            options.Quiet,
            $"Import newer than last check (imported={importedTimestamp}, checked={(string.IsNullOrWhiteSpace(checkedTimestamp) ? "never" : checkedTimestamp)}), running repair...").ConfigureAwait(false);

        var exitCode = await linkRepairCommandHandler.HandleAsync(
            new LinkRepairCommandParsing(
                Mode: LinkRepairMode.Fix,
                Quiet: true,
                BuiltinSpecPath: ContainerRuntimeDefaults.DefaultBuiltinLinkSpec,
                UserSpecPath: ContainerRuntimeDefaults.DefaultUserLinkSpec,
                CheckedAtFilePath: options.CheckedAtPath),
            cancellationToken).ConfigureAwait(false);

        if (exitCode == 0)
        {
            await context.LogInfoAsync(options.Quiet, "Repair completed successfully").ConfigureAwait(false);
            return;
        }

        await context.StandardError.WriteLineAsync("[ERROR] Repair command failed").ConfigureAwait(false);
    }
}
