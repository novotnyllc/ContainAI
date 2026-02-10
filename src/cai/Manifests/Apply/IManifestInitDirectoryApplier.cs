namespace ContainAI.Cli.Host.Manifests.Apply;

internal interface IManifestInitDirectoryApplier
{
    int Apply(string manifestPath, string dataDirectory);
}
