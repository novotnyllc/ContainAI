namespace ContainAI.Cli.Abstractions;

public sealed record DoctorCommandOptions(
    bool Json,
    bool BuildTemplates,
    bool ResetLima);

public sealed record DoctorFixCommandOptions(
    bool All,
    bool DryRun,
    string? Target,
    string? TargetArg);

public sealed record ValidateCommandOptions(
    bool Json);

public sealed record SetupCommandOptions(
    bool DryRun,
    bool Verbose,
    bool SkipTemplates);

public sealed record ImportCommandOptions(
    string? From,
    string? DataVolume,
    string? Workspace,
    string? Config,
    bool DryRun,
    bool NoExcludes,
    bool NoSecrets,
    bool Verbose);

public sealed record ExportCommandOptions(
    string? Output,
    string? DataVolume,
    string? Container,
    string? Workspace);

public sealed record StopCommandOptions(
    bool All,
    string? Container,
    bool Remove,
    bool Force,
    bool Export,
    bool Verbose);

public sealed record GcCommandOptions(
    bool DryRun,
    bool Force,
    bool Images,
    string? Age);

public sealed record UpdateCommandOptions(
    bool DryRun,
    bool StopContainers,
    bool Force,
    bool LimaRecreate,
    bool Verbose);

public sealed record RefreshCommandOptions(
    bool Rebuild,
    bool Verbose);

public sealed record UninstallCommandOptions(
    bool DryRun,
    bool Containers,
    bool Volumes,
    bool Force,
    bool Verbose);
