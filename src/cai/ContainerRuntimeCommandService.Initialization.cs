namespace ContainAI.Cli.Host;

internal sealed partial class ContainerRuntimeCommandService
{
    public ContainerRuntimeCommandService(TextWriter standardOutput, TextWriter standardError)
        : this(standardOutput, standardError, new ManifestTomlParser())
    {
    }

    internal ContainerRuntimeCommandService(
        TextWriter standardOutput,
        TextWriter standardError,
        IManifestTomlParser manifestTomlParser)
    {
        stdout = standardOutput;
        stderr = standardError;
        this.manifestTomlParser = manifestTomlParser ?? throw new ArgumentNullException(nameof(manifestTomlParser));
        devcontainerRuntime = new DevcontainerFeatureRuntime(stdout, stderr);
    }
}
