namespace ContainAI.Cli.Abstractions;

public sealed record ConfigListCommandOptions(
    bool Global,
    string? Workspace,
    bool Verbose);

public sealed record ConfigGetCommandOptions(
    bool Global,
    string? Workspace,
    bool Verbose,
    string Key);

public sealed record ConfigSetCommandOptions(
    bool Global,
    string? Workspace,
    bool Verbose,
    string Key,
    string Value);

public sealed record ConfigUnsetCommandOptions(
    bool Global,
    string? Workspace,
    bool Verbose,
    string Key);

public sealed record ConfigResolveVolumeCommandOptions(
    bool Global,
    string? Workspace,
    bool Verbose,
    string? ExplicitVolume);
