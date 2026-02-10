using ContainAI.Cli.Abstractions;
using ContainAI.Cli.Host.ContainerRuntime.Configuration;

namespace ContainAI.Cli.Host;

internal sealed partial class ContainerRuntimeOptionParser
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
}
