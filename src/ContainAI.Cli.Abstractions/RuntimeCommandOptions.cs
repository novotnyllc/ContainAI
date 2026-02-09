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

public sealed record SshCleanupCommandOptions(
    bool DryRun);

public sealed record LinksSubcommandOptions(
    string? Name,
    string? Container,
    string? Workspace,
    bool DryRun,
    bool Quiet,
    bool Verbose,
    string? Config);

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

public sealed record ManifestParseCommandOptions(
    bool IncludeDisabled,
    bool EmitSourceFile,
    string ManifestPath);

public sealed record ManifestGenerateCommandOptions(
    string Kind,
    string ManifestPath,
    string? OutputPath);

public sealed record ManifestApplyCommandOptions(
    string Kind,
    string ManifestPath,
    string? DataDir,
    string? HomeDir,
    string? ShimDir,
    string? CaiBinary);

public sealed record ManifestCheckCommandOptions(
    string? ManifestDir);

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
