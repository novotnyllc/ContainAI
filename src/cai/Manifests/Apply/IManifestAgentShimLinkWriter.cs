namespace ContainAI.Cli.Host.Manifests.Apply;

internal interface IManifestAgentShimLinkWriter
{
    bool EnsureShimLink(string shimPath, string caiPath);
}
