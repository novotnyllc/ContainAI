namespace ContainAI.Cli.Abstractions;

public sealed record RunCommandOptions(
    string? Workspace,
    bool Fresh,
    bool Detached,
    bool Quiet,
    bool Verbose,
    IReadOnlyList<string> AdditionalArgs,
    IReadOnlyList<string> CommandArgs);

public sealed record ShellCommandOptions(
    string? Workspace,
    bool Quiet,
    bool Verbose,
    IReadOnlyList<string> AdditionalArgs,
    IReadOnlyList<string> CommandArgs);

public sealed record ExecCommandOptions(
    string? Workspace,
    bool Quiet,
    bool Verbose,
    IReadOnlyList<string> AdditionalArgs,
    IReadOnlyList<string> CommandArgs);

public sealed record DockerCommandOptions(
    IReadOnlyList<string> DockerArgs);

public sealed record StatusCommandOptions(
    bool Json,
    string? Workspace,
    string? Container,
    bool Verbose,
    IReadOnlyList<string> AdditionalArgs);
