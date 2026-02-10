namespace ContainAI.Cli.Host;

internal sealed partial class ContainerRuntimeCommandService
{
    private readonly TextWriter stdout;
    private readonly TextWriter stderr;
    private readonly DevcontainerFeatureRuntime devcontainerRuntime;
    private readonly IContainerRuntimeOptionParser optionParser;
    private readonly IManifestTomlParser manifestTomlParser;
}
