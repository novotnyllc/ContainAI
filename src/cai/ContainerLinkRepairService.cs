using System.ComponentModel;
using System.Text.Json.Serialization;

namespace ContainAI.Cli.Host;

internal sealed partial class ContainerLinkRepairService(
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
