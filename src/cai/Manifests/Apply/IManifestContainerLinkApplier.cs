namespace ContainAI.Cli.Host.Manifests.Apply;

internal interface IManifestContainerLinkApplier
{
    int Apply(string manifestPath, string homeDirectory, string dataDirectory);
}
