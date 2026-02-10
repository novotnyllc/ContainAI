namespace ContainAI.Cli.Host.Manifests.Apply;

internal interface IManifestAgentShimApplier
{
    int Apply(string manifestPath, string shimDirectory, string caiExecutablePath);
}
