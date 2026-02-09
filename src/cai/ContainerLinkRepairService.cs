using System.ComponentModel;
using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace ContainAI.Cli.Host;

internal sealed class ContainerLinkRepairService(
    TextWriter standardOutput,
    TextWriter standardError,
    DockerCommandExecutor dockerExecutor)
{
    private const string BuiltinSpecPath = "/usr/local/lib/containai/link-spec.json";
    private const string UserSpecPath = "/mnt/agent-data/containai/user-link-spec.json";
    private const string CheckedAtFilePath = "/mnt/agent-data/.containai-links-checked-at";

    private readonly TextWriter stdout = standardOutput;
    private readonly TextWriter stderr = standardError;
    private readonly DockerCommandExecutor executeDocker = dockerExecutor;

    public async Task<int> RunAsync(
        string containerName,
        ContainerLinkRepairMode mode,
        bool quiet,
        CancellationToken cancellationToken)
    {
        var stats = new LinkRepairStats();

        var builtin = await ReadLinkSpecAsync(containerName, BuiltinSpecPath, required: true, cancellationToken).ConfigureAwait(false);
        if (builtin.Error is not null)
        {
            await stderr.WriteLineAsync($"ERROR: {builtin.Error}").ConfigureAwait(false);
            return 1;
        }

        var user = await ReadLinkSpecAsync(containerName, UserSpecPath, required: false, cancellationToken).ConfigureAwait(false);
        if (user.Error is not null)
        {
            stats.Errors++;
            await stderr.WriteLineAsync($"[WARN] Failed to process user link spec: {user.Error}").ConfigureAwait(false);
        }

        await ProcessEntriesAsync(containerName, builtin.Entries, mode, quiet, stats, cancellationToken).ConfigureAwait(false);
        await ProcessEntriesAsync(containerName, user.Entries, mode, quiet, stats, cancellationToken).ConfigureAwait(false);

        if (mode == ContainerLinkRepairMode.Fix && stats.Errors == 0)
        {
            var timestampResult = await WriteCheckedTimestampAsync(containerName, cancellationToken).ConfigureAwait(false);
            if (!timestampResult.Success)
            {
                stats.Errors++;
                await stderr.WriteLineAsync($"[WARN] Failed to update links-checked-at timestamp: {timestampResult.Error}").ConfigureAwait(false);
            }
            else
            {
                await LogInfoAsync(quiet, "Updated links-checked-at timestamp").ConfigureAwait(false);
            }
        }

        await WriteSummaryAsync(mode, stats, quiet).ConfigureAwait(false);
        if (stats.Errors > 0)
        {
            return 1;
        }

        if (mode == ContainerLinkRepairMode.Check && (stats.Broken + stats.Missing) > 0)
        {
            return 1;
        }

        return 0;
    }

    private async Task ProcessEntriesAsync(
        string containerName,
        IReadOnlyList<ContainerLinkSpecEntry> entries,
        ContainerLinkRepairMode mode,
        bool quiet,
        LinkRepairStats stats,
        CancellationToken cancellationToken)
    {
        foreach (var entry in entries)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (string.IsNullOrWhiteSpace(entry.Link) || string.IsNullOrWhiteSpace(entry.Target))
            {
                stats.Errors++;
                await stderr.WriteLineAsync("[WARN] Skipping invalid link spec entry").ConfigureAwait(false);
                continue;
            }

            await ProcessEntryAsync(containerName, entry, mode, quiet, stats, cancellationToken).ConfigureAwait(false);
        }
    }

    private async Task ProcessEntryAsync(
        string containerName,
        ContainerLinkSpecEntry entry,
        ContainerLinkRepairMode mode,
        bool quiet,
        LinkRepairStats stats,
        CancellationToken cancellationToken)
    {
        var state = await GetEntryStateAsync(containerName, entry, cancellationToken).ConfigureAwait(false);
        switch (state.Kind)
        {
            case EntryStateKind.Ok:
                stats.Ok++;
                return;
            case EntryStateKind.Missing:
                stats.Missing++;
                await LogInfoAsync(quiet, $"[MISSING] {entry.Link} -> {entry.Target}").ConfigureAwait(false);
                break;
            case EntryStateKind.DirectoryConflict when !entry.RemoveFirst:
                stats.Errors++;
                await stderr.WriteLineAsync($"[CONFLICT] {entry.Link} exists as directory (no R flag - cannot fix)").ConfigureAwait(false);
                return;
            case EntryStateKind.DirectoryConflict:
                stats.Broken++;
                await LogInfoAsync(quiet, $"[EXISTS_DIR] {entry.Link} is a directory (will remove with R flag)").ConfigureAwait(false);
                break;
            case EntryStateKind.FileConflict:
                stats.Broken++;
                await LogInfoAsync(quiet, $"[EXISTS_FILE] {entry.Link} is a regular file (will replace)").ConfigureAwait(false);
                break;
            case EntryStateKind.DanglingSymlink:
                stats.Broken++;
                await LogInfoAsync(quiet, $"[BROKEN] {entry.Link} -> {entry.Target} (dangling symlink)").ConfigureAwait(false);
                break;
            case EntryStateKind.WrongTarget:
                stats.Broken++;
                await LogInfoAsync(
                        quiet,
                        $"[WRONG_TARGET] {entry.Link} -> {state.CurrentTarget ?? "<unknown>"} (expected: {entry.Target})")
                    .ConfigureAwait(false);
                break;
            case EntryStateKind.Error:
                stats.Errors++;
                await stderr.WriteLineAsync($"[ERROR] {state.Error ?? "Unknown link inspection error"}").ConfigureAwait(false);
                return;
            default:
                throw new InvalidEnumArgumentException(nameof(state.Kind), (int)state.Kind, typeof(EntryStateKind));
        }

        if (mode == ContainerLinkRepairMode.Check)
        {
            return;
        }

        if (mode == ContainerLinkRepairMode.DryRun)
        {
            await LogInfoAsync(quiet, $"[WOULD] Create symlink: {entry.Link} -> {entry.Target}").ConfigureAwait(false);
            stats.Fixed++;
            return;
        }

        var repair = await RepairEntryAsync(containerName, entry, state, cancellationToken).ConfigureAwait(false);
        if (!repair.Success)
        {
            stats.Errors++;
            await stderr.WriteLineAsync($"ERROR: {repair.Error}").ConfigureAwait(false);
            return;
        }

        stats.Fixed++;
        await LogInfoAsync(quiet, $"[FIXED] {entry.Link} -> {entry.Target}").ConfigureAwait(false);
    }

    private async Task<EntryState> GetEntryStateAsync(
        string containerName,
        ContainerLinkSpecEntry entry,
        CancellationToken cancellationToken)
    {
        var isSymlink = await ExecTestAsync(containerName, "-L", entry.Link, cancellationToken).ConfigureAwait(false);
        if (isSymlink)
        {
            var readResult = await ExecAsync(containerName, ["readlink", "--", entry.Link], cancellationToken).ConfigureAwait(false);
            if (readResult.ExitCode != 0)
            {
                return EntryState.FromError($"Failed to read symlink target for {entry.Link}: {readResult.StandardError.Trim()}");
            }

            var currentTarget = readResult.StandardOutput.Trim();
            if (string.Equals(currentTarget, entry.Target, StringComparison.Ordinal))
            {
                var targetExists = await ExecTestAsync(containerName, "-e", entry.Link, cancellationToken).ConfigureAwait(false);
                return targetExists ? EntryState.Ok() : EntryState.Dangling();
            }

            return EntryState.Wrong(currentTarget);
        }

        if (await ExecTestAsync(containerName, "-d", entry.Link, cancellationToken).ConfigureAwait(false))
        {
            return EntryState.Directory();
        }

        if (await ExecTestAsync(containerName, "-f", entry.Link, cancellationToken).ConfigureAwait(false))
        {
            return EntryState.File();
        }

        return EntryState.Missing();
    }

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

    private async Task<LinkSpecReadResult> ReadLinkSpecAsync(
        string containerName,
        string specPath,
        bool required,
        CancellationToken cancellationToken)
    {
        var read = await ExecAsync(containerName, ["cat", specPath], cancellationToken).ConfigureAwait(false);
        if (read.ExitCode != 0)
        {
            if (required)
            {
                return LinkSpecReadResult.Fail($"Link spec not found: {specPath}");
            }

            return LinkSpecReadResult.Ok(Array.Empty<ContainerLinkSpecEntry>());
        }

        try
        {
            var document = JsonSerializer.Deserialize(
                read.StandardOutput,
                ContainerLinkSpecJsonContext.Default.ContainerLinkSpecDocument);
            if (document?.Links is null)
            {
                return required
                    ? LinkSpecReadResult.Fail($"Invalid link spec format: {specPath}")
                    : LinkSpecReadResult.Ok(Array.Empty<ContainerLinkSpecEntry>());
            }

            return LinkSpecReadResult.Ok(document.Links);
        }
        catch (JsonException ex)
        {
            return LinkSpecReadResult.Fail($"Invalid JSON in {specPath}: {ex.Message}");
        }
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

    private async Task<bool> ExecTestAsync(
        string containerName,
        string testOption,
        string path,
        CancellationToken cancellationToken)
    {
        var result = await ExecAsync(containerName, ["test", testOption, "--", path], cancellationToken).ConfigureAwait(false);
        return result.ExitCode == 0;
    }

    private Task<CommandExecutionResult> ExecAsync(
        string containerName,
        IReadOnlyList<string> command,
        CancellationToken cancellationToken)
    {
        var args = new List<string>(command.Count + 2)
        {
            "exec",
            containerName,
        };
        args.AddRange(command);
        return executeDocker(args, null, cancellationToken);
    }

    private async Task LogInfoAsync(bool quiet, string message)
    {
        if (quiet)
        {
            return;
        }

        await stdout.WriteLineAsync(message).ConfigureAwait(false);
    }

    private async Task WriteSummaryAsync(ContainerLinkRepairMode mode, LinkRepairStats stats, bool quiet)
    {
        if (quiet)
        {
            return;
        }

        await stdout.WriteLineAsync().ConfigureAwait(false);
        await stdout.WriteLineAsync(mode == ContainerLinkRepairMode.DryRun ? "=== Dry-Run Summary ===" : "=== Link Status Summary ===").ConfigureAwait(false);
        await stdout.WriteLineAsync($"  OK:      {stats.Ok}").ConfigureAwait(false);
        await stdout.WriteLineAsync($"  Broken:  {stats.Broken}").ConfigureAwait(false);
        await stdout.WriteLineAsync($"  Missing: {stats.Missing}").ConfigureAwait(false);
        if (mode == ContainerLinkRepairMode.Fix)
        {
            await stdout.WriteLineAsync($"  Fixed:   {stats.Fixed}").ConfigureAwait(false);
        }
        else if (mode == ContainerLinkRepairMode.DryRun)
        {
            await stdout.WriteLineAsync($"  Would fix: {stats.Fixed}").ConfigureAwait(false);
        }

        await stdout.WriteLineAsync($"  Errors:  {stats.Errors}").ConfigureAwait(false);
    }

    private sealed record LinkRepairStats
    {
        public int Ok { get; set; }
        public int Broken { get; set; }
        public int Missing { get; set; }
        public int Fixed { get; set; }
        public int Errors { get; set; }
    }

    private readonly record struct OperationResult(bool Success, string? Error)
    {
        public static OperationResult Ok() => new(true, null);
        public static OperationResult Fail(string error) => new(false, error);
    }

    private readonly record struct LinkSpecReadResult(IReadOnlyList<ContainerLinkSpecEntry> Entries, string? Error)
    {
        public static LinkSpecReadResult Ok(IReadOnlyList<ContainerLinkSpecEntry> entries) => new(entries, null);
        public static LinkSpecReadResult Fail(string error) => new(Array.Empty<ContainerLinkSpecEntry>(), error);
    }

    private readonly record struct EntryState(EntryStateKind Kind, string? CurrentTarget, string? Error)
    {
        public static EntryState Ok() => new(EntryStateKind.Ok, null, null);
        public static EntryState Missing() => new(EntryStateKind.Missing, null, null);
        public static EntryState Directory() => new(EntryStateKind.DirectoryConflict, null, null);
        public static EntryState File() => new(EntryStateKind.FileConflict, null, null);
        public static EntryState Dangling() => new(EntryStateKind.DanglingSymlink, null, null);
        public static EntryState Wrong(string? currentTarget) => new(EntryStateKind.WrongTarget, currentTarget, null);
        public static EntryState FromError(string message) => new(EntryStateKind.Error, null, message);
    }
}

internal enum ContainerLinkRepairMode
{
    Check,
    DryRun,
    Fix,
}

internal enum EntryStateKind
{
    Ok,
    Missing,
    DirectoryConflict,
    FileConflict,
    DanglingSymlink,
    WrongTarget,
    Error,
}

internal delegate Task<CommandExecutionResult> DockerCommandExecutor(
    IReadOnlyList<string> arguments,
    string? standardInput,
    CancellationToken cancellationToken);

internal readonly record struct CommandExecutionResult(int ExitCode, string StandardOutput, string StandardError);

internal sealed record ContainerLinkSpecDocument(
    [property: JsonPropertyName("links")] IReadOnlyList<ContainerLinkSpecEntry> Links);

internal sealed record ContainerLinkSpecEntry(
    [property: JsonPropertyName("link")] string Link,
    [property: JsonPropertyName("target")] string Target,
    [property: JsonPropertyName("remove_first")] bool RemoveFirst);

[JsonSerializable(typeof(ContainerLinkSpecDocument))]
internal sealed partial class ContainerLinkSpecJsonContext : JsonSerializerContext;
