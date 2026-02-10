namespace ContainAI.Cli.Host.Manifests.Apply;

internal interface IManifestAgentShimLinkWriter
{
    bool EnsureShimLink(string shimPath, string caiPath);
}

internal sealed class ManifestAgentShimLinkWriter : IManifestAgentShimLinkWriter
{
    public bool EnsureShimLink(string shimPath, string caiPath)
    {
        var parent = Path.GetDirectoryName(shimPath);
        if (!string.IsNullOrWhiteSpace(parent))
        {
            Directory.CreateDirectory(parent);
        }

        if (ManifestApplyPathOperations.IsSymbolicLink(shimPath))
        {
            var currentTarget = ManifestApplyPathOperations.ResolveLinkTarget(shimPath);
            if (string.Equals(currentTarget, caiPath, StringComparison.Ordinal))
            {
                return false;
            }

            ManifestApplyPathOperations.RemovePath(shimPath);
        }
        else if (File.Exists(shimPath) || Directory.Exists(shimPath))
        {
            return false;
        }

        File.CreateSymbolicLink(shimPath, caiPath);
        return true;
    }
}
