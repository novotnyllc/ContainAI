using System.Text.Json;

namespace ContainAI.Cli.Host;

internal sealed partial class ContainerRuntimeCommandService
{
    private async Task ProcessLinkSpecAsync(
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

        await LogInfoAsync(quiet, $"Processing {specName} ({linksElement.GetArrayLength()} links)").ConfigureAwait(false);

        foreach (var linkElement in linksElement.EnumerateArray())
        {
            cancellationToken.ThrowIfCancellationRequested();
            var linkPath = linkElement.TryGetProperty("link", out var linkValue) ? linkValue.GetString() : null;
            var targetPath = linkElement.TryGetProperty("target", out var targetValue) ? targetValue.GetString() : null;
            var removeFirst = linkElement.TryGetProperty("remove_first", out var removeFirstValue) && removeFirstValue.ValueKind == JsonValueKind.True;
            if (string.IsNullOrWhiteSpace(linkPath) || string.IsNullOrWhiteSpace(targetPath))
            {
                stats.Errors++;
                await stderr.WriteLineAsync($"[WARN] Skipping invalid link spec entry in {specPath}").ConfigureAwait(false);
                continue;
            }

            await ProcessLinkEntryAsync(linkPath!, targetPath!, removeFirst, mode, quiet, stats).ConfigureAwait(false);
        }
    }

    private async Task ProcessLinkEntryAsync(
        string linkPath,
        string targetPath,
        bool removeFirst,
        LinkRepairMode mode,
        bool quiet,
        LinkRepairStats stats)
    {
        var isSymlink = await IsSymlinkAsync(linkPath).ConfigureAwait(false);
        if (isSymlink)
        {
            var currentTarget = await ReadLinkTargetAsync(linkPath).ConfigureAwait(false);
            if (string.Equals(currentTarget, targetPath, StringComparison.Ordinal))
            {
                if (!File.Exists(linkPath) && !Directory.Exists(linkPath))
                {
                    stats.Broken++;
                    await LogInfoAsync(quiet, $"[BROKEN] {linkPath} -> {targetPath} (dangling symlink)").ConfigureAwait(false);
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
                await LogInfoAsync(quiet, $"[WRONG_TARGET] {linkPath} -> {currentTarget} (expected: {targetPath})").ConfigureAwait(false);
            }
        }
        else if (Directory.Exists(linkPath))
        {
            if (removeFirst)
            {
                stats.Broken++;
                await LogInfoAsync(quiet, $"[EXISTS_DIR] {linkPath} is a directory (will remove with R flag)").ConfigureAwait(false);
            }
            else
            {
                stats.Errors++;
                await stderr.WriteLineAsync($"[CONFLICT] {linkPath} exists as directory (no R flag - cannot fix)").ConfigureAwait(false);
                return;
            }
        }
        else if (File.Exists(linkPath))
        {
            stats.Broken++;
            await LogInfoAsync(quiet, $"[EXISTS_FILE] {linkPath} is a regular file (will replace)").ConfigureAwait(false);
        }
        else
        {
            stats.Missing++;
            await LogInfoAsync(quiet, $"[MISSING] {linkPath} -> {targetPath}").ConfigureAwait(false);
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
                await LogInfoAsync(quiet, $"[WOULD] Create parent directory: {parent}").ConfigureAwait(false);
            }
            else
            {
                Directory.CreateDirectory(parent);
            }
        }

        if (Directory.Exists(linkPath) && !await IsSymlinkAsync(linkPath).ConfigureAwait(false))
        {
            if (!removeFirst)
            {
                stats.Errors++;
                await stderr.WriteLineAsync($"ERROR: Cannot fix - directory exists without R flag: {linkPath}").ConfigureAwait(false);
                return;
            }

            if (mode == LinkRepairMode.DryRun)
            {
                await LogInfoAsync(quiet, $"[WOULD] Remove directory: {linkPath}").ConfigureAwait(false);
            }
            else
            {
                Directory.Delete(linkPath, recursive: true);
            }
        }
        else if (File.Exists(linkPath) || await IsSymlinkAsync(linkPath).ConfigureAwait(false))
        {
            if (mode == LinkRepairMode.DryRun)
            {
                await LogInfoAsync(quiet, $"[WOULD] Replace path: {linkPath}").ConfigureAwait(false);
            }
            else
            {
                File.Delete(linkPath);
            }
        }

        if (mode == LinkRepairMode.DryRun)
        {
            await LogInfoAsync(quiet, $"[WOULD] Create symlink: {linkPath} -> {targetPath}").ConfigureAwait(false);
            stats.Fixed++;
            return;
        }

        File.CreateSymbolicLink(linkPath, targetPath);
        await LogInfoAsync(quiet, $"[FIXED] {linkPath} -> {targetPath}").ConfigureAwait(false);
        stats.Fixed++;
    }

    private async Task WriteLinkRepairSummaryAsync(LinkRepairMode mode, LinkRepairStats stats, bool quiet)
    {
        if (quiet)
        {
            return;
        }

        await stdout.WriteLineAsync().ConfigureAwait(false);
        await stdout.WriteLineAsync(mode == LinkRepairMode.DryRun ? "=== Dry-Run Summary ===" : "=== Link Status Summary ===").ConfigureAwait(false);
        await stdout.WriteLineAsync($"  OK:      {stats.Ok}").ConfigureAwait(false);
        await stdout.WriteLineAsync($"  Broken:  {stats.Broken}").ConfigureAwait(false);
        await stdout.WriteLineAsync($"  Missing: {stats.Missing}").ConfigureAwait(false);
        if (mode == LinkRepairMode.Fix)
        {
            await stdout.WriteLineAsync($"  Fixed:   {stats.Fixed}").ConfigureAwait(false);
        }
        else if (mode == LinkRepairMode.DryRun)
        {
            await stdout.WriteLineAsync($"  Would fix: {stats.Fixed}").ConfigureAwait(false);
        }

        await stdout.WriteLineAsync($"  Errors:  {stats.Errors}").ConfigureAwait(false);
    }
}
