namespace ContainAI.Cli.Host;

internal sealed partial class ContainerRuntimeCommandService
{
    public ContainerRuntimeCommandService(TextWriter standardOutput, TextWriter standardError)
        : this(standardOutput, standardError, new ManifestTomlParser(), new ContainerRuntimeOptionParser())
    {
    }

    internal ContainerRuntimeCommandService(
        TextWriter standardOutput,
        TextWriter standardError,
        IManifestTomlParser manifestTomlParser,
        IContainerRuntimeOptionParser optionParser)
    {
        stdout = standardOutput;
        stderr = standardError;
        this.manifestTomlParser = manifestTomlParser ?? throw new ArgumentNullException(nameof(manifestTomlParser));
        this.optionParser = optionParser ?? throw new ArgumentNullException(nameof(optionParser));
        devcontainerRuntime = new DevcontainerFeatureRuntime(stdout, stderr);
    }
}
