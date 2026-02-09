using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed partial class ContainerRuntimeCommandService
{
    private static InitCommandParsing ParseInitCommandOptions(SystemInitCommandOptions options)
        => new(
            Quiet: options.Quiet,
            DataDir: string.IsNullOrWhiteSpace(options.DataDir) ? DefaultDataDir : options.DataDir,
            HomeDir: string.IsNullOrWhiteSpace(options.HomeDir) ? DefaultHomeDir : options.HomeDir,
            ManifestsDir: string.IsNullOrWhiteSpace(options.ManifestsDir) ? DefaultBuiltinManifestsDir : options.ManifestsDir,
            TemplateHooksDir: string.IsNullOrWhiteSpace(options.TemplateHooks) ? DefaultTemplateHooksDir : options.TemplateHooks,
            WorkspaceHooksDir: string.IsNullOrWhiteSpace(options.WorkspaceHooks) ? DefaultWorkspaceHooksDir : options.WorkspaceHooks,
            WorkspaceDir: string.IsNullOrWhiteSpace(options.WorkspaceDir) ? DefaultWorkspaceDir : options.WorkspaceDir);

    private static LinkRepairCommandParsing ParseLinkRepairCommandOptions(SystemLinkRepairCommandOptions options)
        => new(
            Mode: ResolveLinkRepairMode(options),
            Quiet: options.Quiet,
            BuiltinSpecPath: string.IsNullOrWhiteSpace(options.BuiltinSpec) ? DefaultBuiltinLinkSpec : options.BuiltinSpec,
            UserSpecPath: string.IsNullOrWhiteSpace(options.UserSpec) ? DefaultUserLinkSpec : options.UserSpec,
            CheckedAtFilePath: string.IsNullOrWhiteSpace(options.CheckedAtFile) ? DefaultCheckedAtFile : options.CheckedAtFile);

    private static WatchLinksCommandParsing ParseWatchLinksCommandOptions(SystemWatchLinksCommandOptions options)
    {
        var pollIntervalSeconds = 60;
        if (!string.IsNullOrWhiteSpace(options.PollInterval) &&
            (!int.TryParse(options.PollInterval, out pollIntervalSeconds) || pollIntervalSeconds < 1))
        {
            return WatchLinksCommandParsing.Invalid("--poll-interval requires a positive integer value");
        }

        return WatchLinksCommandParsing.Valid(
            pollIntervalSeconds: pollIntervalSeconds,
            importedAtPath: string.IsNullOrWhiteSpace(options.ImportedAtFile) ? DefaultImportedAtFile : options.ImportedAtFile,
            checkedAtPath: string.IsNullOrWhiteSpace(options.CheckedAtFile) ? DefaultCheckedAtFile : options.CheckedAtFile,
            quiet: options.Quiet);
    }

    private readonly record struct InitCommandParsing(
        bool Quiet,
        string DataDir,
        string HomeDir,
        string ManifestsDir,
        string TemplateHooksDir,
        string WorkspaceHooksDir,
        string WorkspaceDir);

    private readonly record struct LinkRepairCommandParsing(
        LinkRepairMode Mode,
        bool Quiet,
        string BuiltinSpecPath,
        string UserSpecPath,
        string CheckedAtFilePath);

    private readonly record struct WatchLinksCommandParsing(
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
}
