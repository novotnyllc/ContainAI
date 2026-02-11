using ContainAI.Cli.Host.ContainerRuntime.Infrastructure;
using ContainAI.Cli.Host.ContainerRuntime.Models;

namespace ContainAI.Cli.Host.ContainerRuntime.Handlers;

internal interface IContainerRuntimeLinkCreationService
{
    Task CreateAsync(
        string linkPath,
        string targetPath,
        LinkRepairMode mode,
        bool quiet,
        LinkRepairStats stats);
}

internal sealed class ContainerRuntimeLinkCreationService : IContainerRuntimeLinkCreationService
{
    private readonly IContainerRuntimeExecutionContext context;

    public ContainerRuntimeLinkCreationService(IContainerRuntimeExecutionContext context)
        => this.context = context ?? throw new ArgumentNullException(nameof(context));

    public async Task CreateAsync(
        string linkPath,
        string targetPath,
        LinkRepairMode mode,
        bool quiet,
        LinkRepairStats stats)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(linkPath);
        ArgumentException.ThrowIfNullOrWhiteSpace(targetPath);
        ArgumentNullException.ThrowIfNull(stats);

        if (mode == LinkRepairMode.DryRun)
        {
            await context.LogInfoAsync(quiet, $"[WOULD] Create symlink: {linkPath} -> {targetPath}").ConfigureAwait(false);
            stats.Fixed++;
            return;
        }

        File.CreateSymbolicLink(linkPath, targetPath);
        await context.LogInfoAsync(quiet, $"[FIXED] {linkPath} -> {targetPath}").ConfigureAwait(false);
        stats.Fixed++;
    }
}
