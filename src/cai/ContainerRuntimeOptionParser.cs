using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal interface IContainerRuntimeOptionParser
{
    InitCommandParsing ParseInitCommandOptions(SystemInitCommandOptions options);

    LinkRepairCommandParsing ParseLinkRepairCommandOptions(SystemLinkRepairCommandOptions options);

    WatchLinksCommandParsing ParseWatchLinksCommandOptions(SystemWatchLinksCommandOptions options);
}

internal sealed class ContainerRuntimeOptionParser : IContainerRuntimeOptionParser
{
    public InitCommandParsing ParseInitCommandOptions(SystemInitCommandOptions options)
        => new(
            Quiet: options.Quiet,
            DataDir: string.IsNullOrWhiteSpace(options.DataDir) ? ContainerRuntimeDefaults.DefaultDataDir : options.DataDir,
            HomeDir: string.IsNullOrWhiteSpace(options.HomeDir) ? ContainerRuntimeDefaults.DefaultHomeDir : options.HomeDir,
            ManifestsDir: string.IsNullOrWhiteSpace(options.ManifestsDir) ? ContainerRuntimeDefaults.DefaultBuiltinManifestsDir : options.ManifestsDir,
            TemplateHooksDir: string.IsNullOrWhiteSpace(options.TemplateHooks) ? ContainerRuntimeDefaults.DefaultTemplateHooksDir : options.TemplateHooks,
            WorkspaceHooksDir: string.IsNullOrWhiteSpace(options.WorkspaceHooks) ? ContainerRuntimeDefaults.DefaultWorkspaceHooksDir : options.WorkspaceHooks,
            WorkspaceDir: string.IsNullOrWhiteSpace(options.WorkspaceDir) ? ContainerRuntimeDefaults.DefaultWorkspaceDir : options.WorkspaceDir);

    public LinkRepairCommandParsing ParseLinkRepairCommandOptions(SystemLinkRepairCommandOptions options)
        => new(
            Mode: ContainerRuntimeDefaults.ResolveLinkRepairMode(options),
            Quiet: options.Quiet,
            BuiltinSpecPath: string.IsNullOrWhiteSpace(options.BuiltinSpec) ? ContainerRuntimeDefaults.DefaultBuiltinLinkSpec : options.BuiltinSpec,
            UserSpecPath: string.IsNullOrWhiteSpace(options.UserSpec) ? ContainerRuntimeDefaults.DefaultUserLinkSpec : options.UserSpec,
            CheckedAtFilePath: string.IsNullOrWhiteSpace(options.CheckedAtFile) ? ContainerRuntimeDefaults.DefaultCheckedAtFile : options.CheckedAtFile);

    public WatchLinksCommandParsing ParseWatchLinksCommandOptions(SystemWatchLinksCommandOptions options)
    {
        var pollIntervalSeconds = 60;
        if (!string.IsNullOrWhiteSpace(options.PollInterval) &&
            (!int.TryParse(options.PollInterval, out pollIntervalSeconds) || pollIntervalSeconds < 1))
        {
            return WatchLinksCommandParsing.Invalid("--poll-interval requires a positive integer value");
        }

        return WatchLinksCommandParsing.Valid(
            pollIntervalSeconds: pollIntervalSeconds,
            importedAtPath: string.IsNullOrWhiteSpace(options.ImportedAtFile) ? ContainerRuntimeDefaults.DefaultImportedAtFile : options.ImportedAtFile,
            checkedAtPath: string.IsNullOrWhiteSpace(options.CheckedAtFile) ? ContainerRuntimeDefaults.DefaultCheckedAtFile : options.CheckedAtFile,
            quiet: options.Quiet);
    }
}

internal readonly record struct InitCommandParsing(
    bool Quiet,
    string DataDir,
    string HomeDir,
    string ManifestsDir,
    string TemplateHooksDir,
    string WorkspaceHooksDir,
    string WorkspaceDir);

internal readonly record struct LinkRepairCommandParsing(
    LinkRepairMode Mode,
    bool Quiet,
    string BuiltinSpecPath,
    string UserSpecPath,
    string CheckedAtFilePath);

internal readonly record struct WatchLinksCommandParsing(
    bool IsValid,
    int PollIntervalSeconds,
    string ImportedAtPath,
    string CheckedAtPath,
    bool Quiet,
    string? ErrorMessage)
{
    public static WatchLinksCommandParsing Invalid(string errorMessage)
        => new(
            IsValid: false,
            PollIntervalSeconds: default,
            ImportedAtPath: string.Empty,
            CheckedAtPath: string.Empty,
            Quiet: false,
            ErrorMessage: errorMessage);

    public static WatchLinksCommandParsing Valid(int pollIntervalSeconds, string importedAtPath, string checkedAtPath, bool quiet)
        => new(
            IsValid: true,
            PollIntervalSeconds: pollIntervalSeconds,
            ImportedAtPath: importedAtPath,
            CheckedAtPath: checkedAtPath,
            Quiet: quiet,
            ErrorMessage: null);
}
