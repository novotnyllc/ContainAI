using ContainAI.Cli.Host.ContainerRuntime.Models;

namespace ContainAI.Cli.Host.ContainerRuntime.Configuration;

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
