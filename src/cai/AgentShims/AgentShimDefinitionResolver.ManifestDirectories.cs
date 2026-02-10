namespace ContainAI.Cli.Host.AgentShims;

internal sealed partial class AgentShimDefinitionResolver
{
    private static string[] ResolveManifestDirectories()
    {
        var candidates = new List<string>();

        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        if (!string.IsNullOrWhiteSpace(home))
        {
            candidates.Add(Path.Combine(home, ".config", "containai", "manifests"));
        }

        candidates.Add("/mnt/agent-data/containai/manifests");

        var installRoot = InstallMetadata.ResolveInstallDirectory();
        if (!string.IsNullOrWhiteSpace(installRoot))
        {
            candidates.Add(Path.Combine(installRoot, "manifests"));
        }

        candidates.Add("/opt/containai/manifests");
        candidates.Add(Path.Combine(Directory.GetCurrentDirectory(), "src", "manifests"));

        return candidates
            .Where(Directory.Exists)
            .Distinct(StringComparer.Ordinal)
            .ToArray();
    }
}
