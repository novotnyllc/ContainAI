using ContainAI.Cli.Abstractions;
using ContainAI.Cli.Host.ContainerRuntime.Models;
using ContainAI.Cli.Host.ContainerRuntime.Configuration;

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
