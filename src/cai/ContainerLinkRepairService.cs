using System.Text.Json.Serialization;

namespace ContainAI.Cli.Host;

internal sealed class ContainerLinkRepairService
{
    private const string BuiltinSpecPath = "/usr/local/lib/containai/link-spec.json";
    private const string UserSpecPath = "/mnt/agent-data/containai/user-link-spec.json";
    private const string CheckedAtFilePath = "/mnt/agent-data/.containai-links-checked-at";

    private readonly TextWriter stderr;
    private readonly ContainerLinkSpecReader specReader;
    private readonly ContainerLinkRepairOperations repairOperations;
    private readonly ContainerLinkRepairReporter reporter;
    private readonly ContainerLinkEntryProcessor entryProcessor;

    public ContainerLinkRepairService(
        TextWriter standardOutput,
        TextWriter standardError,
        DockerCommandExecutor dockerExecutor)
    {
        ArgumentNullException.ThrowIfNull(standardOutput);
        ArgumentNullException.ThrowIfNull(standardError);
        ArgumentNullException.ThrowIfNull(dockerExecutor);

        stderr = standardError;

        var commandClient = new ContainerLinkCommandClient(dockerExecutor);
        specReader = new ContainerLinkSpecReader(commandClient);
        repairOperations = new ContainerLinkRepairOperations(commandClient);
        reporter = new ContainerLinkRepairReporter(standardOutput);
        entryProcessor = new ContainerLinkEntryProcessor(standardError, new ContainerLinkEntryInspector(commandClient), repairOperations, reporter);
    }

    public async Task<int> RunAsync(
        string containerName,
        ContainerLinkRepairMode mode,
        bool quiet,
        CancellationToken cancellationToken)
    {
        var stats = new ContainerLinkRepairStats();

        var builtin = await specReader.ReadLinkSpecAsync(containerName, BuiltinSpecPath, required: true, cancellationToken).ConfigureAwait(false);
        if (builtin.Error is not null)
        {
            await stderr.WriteLineAsync($"ERROR: {builtin.Error}").ConfigureAwait(false);
            return 1;
        }

        var user = await specReader.ReadLinkSpecAsync(containerName, UserSpecPath, required: false, cancellationToken).ConfigureAwait(false);
        if (user.Error is not null)
        {
            stats.Errors++;
            await stderr.WriteLineAsync($"[WARN] Failed to process user link spec: {user.Error}").ConfigureAwait(false);
        }

        await entryProcessor.ProcessEntriesAsync(containerName, builtin.Entries, mode, quiet, stats, cancellationToken).ConfigureAwait(false);
        await entryProcessor.ProcessEntriesAsync(containerName, user.Entries, mode, quiet, stats, cancellationToken).ConfigureAwait(false);

        if (mode == ContainerLinkRepairMode.Fix && stats.Errors == 0)
        {
            var timestampResult = await repairOperations.WriteCheckedTimestampAsync(containerName, CheckedAtFilePath, cancellationToken).ConfigureAwait(false);
            if (!timestampResult.Success)
            {
                stats.Errors++;
                await stderr.WriteLineAsync($"[WARN] Failed to update links-checked-at timestamp: {timestampResult.Error}").ConfigureAwait(false);
            }
            else
            {
                await reporter.LogInfoAsync(quiet, "Updated links-checked-at timestamp").ConfigureAwait(false);
            }
        }

        await reporter.WriteSummaryAsync(mode, stats, quiet).ConfigureAwait(false);
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
