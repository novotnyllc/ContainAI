namespace ContainAI.Cli.Host.ConfigManifest;

internal sealed class ManifestDirectoryResolver : IManifestDirectoryResolver
{
    private readonly Func<string, string> expandHomePath;

    public ManifestDirectoryResolver(Func<string, string> expandHomePath) =>
        this.expandHomePath = expandHomePath ?? throw new ArgumentNullException(nameof(expandHomePath));

    public string ResolveManifestDirectory(string? userProvidedPath)
    {
        if (!string.IsNullOrWhiteSpace(userProvidedPath))
        {
            return Path.GetFullPath(expandHomePath(userProvidedPath));
        }

        var candidates = ResolveManifestDirectoryCandidates();
        foreach (var candidate in candidates)
        {
            if (Directory.Exists(candidate))
            {
                return candidate;
            }
        }

        return candidates[0];
    }

    private static string[] ResolveManifestDirectoryCandidates()
    {
        var candidates = new List<string>();
        var seen = new HashSet<string>(StringComparer.Ordinal);

        AddCandidate(candidates, seen, Path.Combine(InstallMetadata.ResolveInstallDirectory(), "manifests"));
        AddCandidate(candidates, seen, Path.Combine(InstallMetadata.ResolveInstallDirectory(), "src", "manifests"));

        var appBase = Path.GetFullPath(AppContext.BaseDirectory);
        AddCandidate(candidates, seen, Path.Combine(appBase, "manifests"));
        AddCandidate(candidates, seen, Path.Combine(appBase, "..", "manifests"));
        AddCandidate(candidates, seen, Path.Combine(appBase, "..", "..", "manifests"));
        AddCandidate(candidates, seen, Path.Combine(appBase, "..", "..", "..", "manifests"));

        var current = Directory.GetCurrentDirectory();
        AddCandidate(candidates, seen, Path.Combine(current, "manifests"));
        AddCandidate(candidates, seen, Path.Combine(current, "src", "manifests"));

        AddCandidate(candidates, seen, "/opt/containai/manifests");
        return candidates.ToArray();
    }

    private static void AddCandidate(List<string> target, HashSet<string> seenSet, string? path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return;
        }

        var fullPath = Path.GetFullPath(path);
        if (seenSet.Add(fullPath))
        {
            target.Add(fullPath);
        }
    }
}
