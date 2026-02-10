using System.Text.Json;
using ContainAI.Cli.Host.ContainerRuntime.Infrastructure;
using ContainAI.Cli.Host.ContainerRuntime.Models;

namespace ContainAI.Cli.Host.ContainerRuntime.Handlers;

internal interface IContainerRuntimeLinkSpecProcessor
{
    Task ProcessLinkSpecAsync(
        string specPath,
        LinkRepairMode mode,
        bool quiet,
        string specName,
        LinkRepairStats stats,
        CancellationToken cancellationToken);

    Task WriteSummaryAsync(LinkRepairMode mode, LinkRepairStats stats, bool quiet);
}

internal sealed class ContainerRuntimeLinkSpecProcessor : IContainerRuntimeLinkSpecProcessor
{
    private readonly IContainerRuntimeExecutionContext context;

    public ContainerRuntimeLinkSpecProcessor(IContainerRuntimeExecutionContext context)
        => this.context = context ?? throw new ArgumentNullException(nameof(context));

    public async Task ProcessLinkSpecAsync(
        string specPath,
        LinkRepairMode mode,
        bool quiet,
        string specName,
        LinkRepairStats stats,
        CancellationToken cancellationToken)
    {
        var json = await File.ReadAllTextAsync(specPath, cancellationToken).ConfigureAwait(false);
        using var document = JsonDocument.Parse(json);
        if (!document.RootElement.TryGetProperty("links", out var linksElement) || linksElement.ValueKind != JsonValueKind.Array)
        {
            throw new InvalidOperationException($"Invalid link spec format: {specPath}");
        }

        await context.LogInfoAsync(quiet, $"Processing {specName} ({linksElement.GetArrayLength()} links)").ConfigureAwait(false);

        foreach (var linkElement in linksElement.EnumerateArray())
        {
            cancellationToken.ThrowIfCancellationRequested();
            var linkPath = linkElement.TryGetProperty("link", out var linkValue) ? linkValue.GetString() : null;
            var targetPath = linkElement.TryGetProperty("target", out var targetValue) ? targetValue.GetString() : null;
            var removeFirst = linkElement.TryGetProperty("remove_first", out var removeFirstValue) && removeFirstValue.ValueKind == JsonValueKind.True;
            if (string.IsNullOrWhiteSpace(linkPath) || string.IsNullOrWhiteSpace(targetPath))
            {
                stats.Errors++;
                await context.StandardError.WriteLineAsync($"[WARN] Skipping invalid link spec entry in {specPath}").ConfigureAwait(false);
                continue;
            }

            await ProcessLinkEntryAsync(linkPath!, targetPath!, removeFirst, mode, quiet, stats).ConfigureAwait(false);
        }
    }

    public async Task WriteSummaryAsync(LinkRepairMode mode, LinkRepairStats stats, bool quiet)
    {
        if (quiet)
        {
            return;
        }

        await context.StandardOutput.WriteLineAsync().ConfigureAwait(false);
        await context.StandardOutput.WriteLineAsync(mode == LinkRepairMode.DryRun ? "=== Dry-Run Summary ===" : "=== Link Status Summary ===").ConfigureAwait(false);
        await context.StandardOutput.WriteLineAsync($"  OK:      {stats.Ok}").ConfigureAwait(false);
        await context.StandardOutput.WriteLineAsync($"  Broken:  {stats.Broken}").ConfigureAwait(false);
        await context.StandardOutput.WriteLineAsync($"  Missing: {stats.Missing}").ConfigureAwait(false);
        if (mode == LinkRepairMode.Fix)
        {
            await context.StandardOutput.WriteLineAsync($"  Fixed:   {stats.Fixed}").ConfigureAwait(false);
        }
        else if (mode == LinkRepairMode.DryRun)
        {
            await context.StandardOutput.WriteLineAsync($"  Would fix: {stats.Fixed}").ConfigureAwait(false);
        }

        await context.StandardOutput.WriteLineAsync($"  Errors:  {stats.Errors}").ConfigureAwait(false);
    }

    private async Task ProcessLinkEntryAsync(
        string linkPath,
        string targetPath,
        bool removeFirst,
        LinkRepairMode mode,
        bool quiet,
        LinkRepairStats stats)
    {
        var isSymlink = await context.IsSymlinkAsync(linkPath).ConfigureAwait(false);
        if (isSymlink)
        {
            var currentTarget = await context.ReadLinkTargetAsync(linkPath).ConfigureAwait(false);
            if (string.Equals(currentTarget, targetPath, StringComparison.Ordinal))
            {
                if (!File.Exists(linkPath) && !Directory.Exists(linkPath))
                {
                    stats.Broken++;
                    await context.LogInfoAsync(quiet, $"[BROKEN] {linkPath} -> {targetPath} (dangling symlink)").ConfigureAwait(false);
                }
                else
                {
                    stats.Ok++;
                    return;
                }
            }
            else
            {
                stats.Broken++;
                await context.LogInfoAsync(quiet, $"[WRONG_TARGET] {linkPath} -> {currentTarget} (expected: {targetPath})").ConfigureAwait(false);
            }
        }
        else if (Directory.Exists(linkPath))
        {
            if (removeFirst)
            {
                stats.Broken++;
                await context.LogInfoAsync(quiet, $"[EXISTS_DIR] {linkPath} is a directory (will remove with R flag)").ConfigureAwait(false);
            }
            else
            {
                stats.Errors++;
                await context.StandardError.WriteLineAsync($"[CONFLICT] {linkPath} exists as directory (no R flag - cannot fix)").ConfigureAwait(false);
                return;
            }
        }
        else if (File.Exists(linkPath))
        {
            stats.Broken++;
            await context.LogInfoAsync(quiet, $"[EXISTS_FILE] {linkPath} is a regular file (will replace)").ConfigureAwait(false);
        }
        else
        {
            stats.Missing++;
            await context.LogInfoAsync(quiet, $"[MISSING] {linkPath} -> {targetPath}").ConfigureAwait(false);
        }

        if (mode == LinkRepairMode.Check)
        {
            return;
        }

        var parent = Path.GetDirectoryName(linkPath);
        if (!string.IsNullOrWhiteSpace(parent) && !Directory.Exists(parent))
        {
            if (mode == LinkRepairMode.DryRun)
            {
                await context.LogInfoAsync(quiet, $"[WOULD] Create parent directory: {parent}").ConfigureAwait(false);
            }
            else
            {
                Directory.CreateDirectory(parent);
            }
        }

        if (Directory.Exists(linkPath) && !await context.IsSymlinkAsync(linkPath).ConfigureAwait(false))
        {
            if (!removeFirst)
            {
                stats.Errors++;
                await context.StandardError.WriteLineAsync($"ERROR: Cannot fix - directory exists without R flag: {linkPath}").ConfigureAwait(false);
                return;
            }

            if (mode == LinkRepairMode.DryRun)
            {
                await context.LogInfoAsync(quiet, $"[WOULD] Remove directory: {linkPath}").ConfigureAwait(false);
            }
            else
            {
                Directory.Delete(linkPath, recursive: true);
            }
        }
        else if (File.Exists(linkPath) || await context.IsSymlinkAsync(linkPath).ConfigureAwait(false))
        {
            if (mode == LinkRepairMode.DryRun)
            {
                await context.LogInfoAsync(quiet, $"[WOULD] Replace path: {linkPath}").ConfigureAwait(false);
            }
            else
            {
                File.Delete(linkPath);
            }
        }

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
