namespace ContainAI.Cli.Host;

internal interface IImportManifestCatalog
{
    string ResolveDirectory();
}

internal sealed class CaiImportManifestCatalog
    : IImportManifestCatalog
{
    private readonly string manifestsDirectoryName = "manifests";

    public string ResolveDirectory()
    {
        var candidates = ResolveDirectoryCandidates();
        foreach (var candidate in candidates)
        {
            if (Directory.Exists(candidate))
            {
                return candidate;
            }
        }

        throw new InvalidOperationException($"manifest directory not found; tried: {string.Join(", ", candidates)}");
    }

    private string[] ResolveDirectoryCandidates()
    {
        var candidates = new List<string>();
        var seen = new HashSet<string>(StringComparer.Ordinal);

        static void AddCandidate(ICollection<string> target, ISet<string> seenSet, string? path)
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

        var installRoot = InstallMetadata.ResolveInstallDirectory();
        AddCandidate(candidates, seen, Path.Combine(installRoot, manifestsDirectoryName));
        AddCandidate(candidates, seen, Path.Combine(installRoot, "src", manifestsDirectoryName));

        var appBase = Path.GetFullPath(AppContext.BaseDirectory);
        AddCandidate(candidates, seen, Path.Combine(appBase, manifestsDirectoryName));
        AddCandidate(candidates, seen, Path.Combine(appBase, "..", manifestsDirectoryName));
        AddCandidate(candidates, seen, Path.Combine(appBase, "..", "..", manifestsDirectoryName));
        AddCandidate(candidates, seen, Path.Combine(appBase, "..", "..", "..", manifestsDirectoryName));

        var current = Directory.GetCurrentDirectory();
        AddCandidate(candidates, seen, Path.Combine(current, manifestsDirectoryName));
        AddCandidate(candidates, seen, Path.Combine(current, "src", manifestsDirectoryName));

        AddCandidate(candidates, seen, Path.Combine("/opt/containai", manifestsDirectoryName));
        return candidates.ToArray();
    }
}
