namespace ContainAI.Cli.Abstractions;

public sealed record TemplateUpgradeCommandOptions(
    string? Name,
    bool DryRun);

public sealed record SystemInitCommandOptions(
    string? DataDir,
    string? HomeDir,
    string? ManifestsDir,
    string? TemplateHooks,
    string? WorkspaceHooks,
    string? WorkspaceDir,
    bool Quiet);

public sealed record SystemLinkRepairCommandOptions(
    bool Check,
    bool Fix,
    bool DryRun,
    bool Quiet,
    string? BuiltinSpec,
    string? UserSpec,
    string? CheckedAtFile);

public sealed record SystemWatchLinksCommandOptions(
    string? PollInterval,
    string? ImportedAtFile,
    string? CheckedAtFile,
    bool Quiet);

public sealed record SystemDevcontainerInstallCommandOptions(
    string? FeatureDir);
