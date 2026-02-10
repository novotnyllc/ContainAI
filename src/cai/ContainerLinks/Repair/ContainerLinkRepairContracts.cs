using System.Text.Json.Serialization;

namespace ContainAI.Cli.Host;

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
