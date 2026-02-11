using ContainAI.Cli.Abstractions;
using ContainAI.Cli.Host.ContainerRuntime.Models;

namespace ContainAI.Cli.Host.ContainerRuntime.Configuration;

internal static class ContainerRuntimeDefaults
{
    public const string DefaultDataDir = "/mnt/agent-data";
    public const string DefaultHomeDir = "/home/agent";
    public const string DefaultWorkspaceDir = "/home/agent/workspace";
    public const string DefaultBuiltinManifestsDir = "/opt/containai/manifests";
    public const string DefaultTemplateHooksDir = "/etc/containai/template-hooks/startup.d";
    public const string DefaultWorkspaceHooksDir = "/home/agent/workspace/.containai/hooks/startup.d";
    public const string DefaultBuiltinLinkSpec = "/usr/local/lib/containai/link-spec.json";
    public const string DefaultUserLinkSpec = "/mnt/agent-data/containai/user-link-spec.json";
    public const string DefaultImportedAtFile = "/mnt/agent-data/.containai-imported-at";
    public const string DefaultCheckedAtFile = "/mnt/agent-data/.containai-links-checked-at";

    public static LinkRepairMode ResolveLinkRepairMode(SystemLinkRepairCommandOptions options)
    {
        if (options.DryRun)
        {
            return LinkRepairMode.DryRun;
        }

        if (options.Fix)
        {
            return LinkRepairMode.Fix;
        }

        return LinkRepairMode.Check;
    }
}
