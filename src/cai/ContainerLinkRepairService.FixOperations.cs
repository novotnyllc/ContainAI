using System.Globalization;

namespace ContainAI.Cli.Host;

internal sealed partial class ContainerLinkRepairService
{
    private async Task<OperationResult> RepairEntryAsync(
        string containerName,
        ContainerLinkSpecEntry entry,
        EntryState state,
        CancellationToken cancellationToken)
    {
        var parent = Path.GetDirectoryName(entry.Link);
        if (!string.IsNullOrWhiteSpace(parent))
        {
            var mkdir = await ExecAsync(containerName, ["mkdir", "-p", parent], cancellationToken).ConfigureAwait(false);
            if (mkdir.ExitCode != 0)
            {
                return OperationResult.Fail($"Failed to create parent directory '{parent}': {mkdir.StandardError.Trim()}");
            }
        }

        if (state.Kind is not EntryStateKind.Missing)
        {
            if (state.Kind == EntryStateKind.DirectoryConflict && !entry.RemoveFirst)
            {
                return OperationResult.Fail($"Cannot fix - directory exists without R flag: {entry.Link}");
            }

            var remove = await ExecAsync(containerName, ["rm", "-rf", "--", entry.Link], cancellationToken).ConfigureAwait(false);
            if (remove.ExitCode != 0)
            {
                return OperationResult.Fail($"Failed to remove '{entry.Link}': {remove.StandardError.Trim()}");
            }
        }

        var link = await ExecAsync(containerName, ["ln", "-sfn", "--", entry.Target, entry.Link], cancellationToken).ConfigureAwait(false);
        if (link.ExitCode != 0)
        {
            return OperationResult.Fail($"Failed to create symlink '{entry.Link}' -> '{entry.Target}': {link.StandardError.Trim()}");
        }

        return OperationResult.Ok();
    }

    private async Task<OperationResult> WriteCheckedTimestampAsync(string containerName, CancellationToken cancellationToken)
    {
        var timestamp = DateTimeOffset.UtcNow.ToString("yyyyMMddHHmmss", CultureInfo.InvariantCulture);
        var write = await executeDocker(
                ["exec", "-i", containerName, "tee", CheckedAtFilePath],
                timestamp + Environment.NewLine,
                cancellationToken)
            .ConfigureAwait(false);
        if (write.ExitCode != 0)
        {
            return OperationResult.Fail(write.StandardError.Trim());
        }

        var chown = await ExecAsync(containerName, ["chown", "1000:1000", CheckedAtFilePath], cancellationToken).ConfigureAwait(false);
        if (chown.ExitCode != 0)
        {
            return OperationResult.Fail(chown.StandardError.Trim());
        }

        return OperationResult.Ok();
    }

    private readonly record struct OperationResult(bool Success, string? Error)
    {
        public static OperationResult Ok() => new(true, null);
        public static OperationResult Fail(string error) => new(false, error);
    }
}
