namespace ContainAI.Cli.Host.Manifests.Apply;

internal interface IManifestApplier
{
    int ApplyContainerLinks(string manifestPath, string homeDirectory, string dataDirectory);

    int ApplyInitDirs(string manifestPath, string dataDirectory);

    int ApplyAgentShims(string manifestPath, string shimDirectory, string caiExecutablePath);
}
