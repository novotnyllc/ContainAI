namespace ContainAI.Cli.Abstractions;

public sealed record RunCommandOptions(
    string? Workspace,
    bool Fresh,
    bool Detached,
    bool Quiet,
    bool Verbose,
    string? Credentials,
    bool AcknowledgeCredentialRisk,
    string? DataVolume,
    string? Config,
    string? Container,
    bool Force,
    bool Debug,
    bool DryRun,
    string? ImageTag,
    string? Template,
    string? Channel,
    string? Memory,
    string? Cpus,
    IReadOnlyList<string> Env,
    IReadOnlyList<string> CommandArgs);

public sealed record ShellCommandOptions(
    string? Workspace,
    bool Fresh,
    bool Reset,
    bool Quiet,
    bool Verbose,
    string? DataVolume,
    string? Config,
    string? Container,
    bool Force,
    bool Debug,
    bool DryRun,
    string? ImageTag,
    string? Template,
    string? Channel,
    string? Memory,
    string? Cpus,
    IReadOnlyList<string> CommandArgs);

public sealed record ExecCommandOptions(
    string? Workspace,
    bool Quiet,
    bool Verbose,
    string? Container,
    string? Template,
    string? Channel,
    string? DataVolume,
    string? Config,
    bool Fresh,
    bool Force,
    bool Debug,
    IReadOnlyList<string> CommandArgs);

public sealed record DockerCommandOptions(
    IReadOnlyList<string> DockerArgs);

public sealed record StatusCommandOptions(
    bool Json,
    string? Workspace,
    string? Container,
    bool Verbose);

public sealed record InstallCommandOptions(
    bool Local,
    bool Yes,
    bool NoSetup,
    string? InstallDir,
    string? BinDir,
    string? Channel,
    bool Verbose);

public sealed record ExamplesExportCommandOptions(
    string OutputDir,
    bool Force);
