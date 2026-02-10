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
