namespace ContainAI.Cli.Host.Manifests.Apply;

internal sealed partial class ManifestAgentShimApplier
{
    private static (string ShimRoot, string CaiPath) ValidateAndResolvePaths(string shimDirectory, string caiExecutablePath)
    {
        if (!Path.IsPathRooted(shimDirectory))
        {
            throw new InvalidOperationException($"shim directory must be absolute: {shimDirectory}");
        }

        if (!Path.IsPathRooted(caiExecutablePath))
        {
            throw new InvalidOperationException($"cai executable path must be absolute: {caiExecutablePath}");
        }

        return (Path.GetFullPath(shimDirectory), Path.GetFullPath(caiExecutablePath));
    }
}
