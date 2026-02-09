namespace ContainAI.Cli.Host;

internal sealed partial class ContainerRuntimeCommandService
{
    public ContainerRuntimeCommandService(TextWriter standardOutput, TextWriter standardError)
    {
        stdout = standardOutput;
        stderr = standardError;
        devcontainerRuntime = new DevcontainerFeatureRuntime(stdout, stderr);
    }
}
