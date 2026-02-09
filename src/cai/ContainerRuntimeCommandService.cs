namespace ContainAI.Cli.Host;

internal sealed partial class ContainerRuntimeCommandService
{
    private const string DefaultDataDir = "/mnt/agent-data";
    private const string DefaultHomeDir = "/home/agent";
    private const string DefaultWorkspaceDir = "/home/agent/workspace";
    private const string DefaultBuiltinManifestsDir = "/opt/containai/manifests";
    private const string DefaultTemplateHooksDir = "/etc/containai/template-hooks/startup.d";
    private const string DefaultWorkspaceHooksDir = "/home/agent/workspace/.containai/hooks/startup.d";
    private const string DefaultBuiltinLinkSpec = "/usr/local/lib/containai/link-spec.json";
    private const string DefaultUserLinkSpec = "/mnt/agent-data/containai/user-link-spec.json";
    private const string DefaultImportedAtFile = "/mnt/agent-data/.containai-imported-at";
    private const string DefaultCheckedAtFile = "/mnt/agent-data/.containai-links-checked-at";

    private readonly TextWriter stdout;
    private readonly TextWriter stderr;
    private readonly DevcontainerFeatureRuntime devcontainerRuntime;

    public ContainerRuntimeCommandService(TextWriter standardOutput, TextWriter standardError)
    {
        stdout = standardOutput;
        stderr = standardError;
        devcontainerRuntime = new DevcontainerFeatureRuntime(stdout, stderr);
    }
}
