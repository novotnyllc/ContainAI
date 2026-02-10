namespace ContainAI.Cli.Host.Manifests.Apply;

internal interface IManifestAgentShimBinaryResolver
{
    string? ResolveBinaryPath(string binary, string shimRoot, string caiPath);
}

internal sealed class ManifestAgentShimBinaryResolver : IManifestAgentShimBinaryResolver
{
    public string? ResolveBinaryPath(string binary, string shimRoot, string caiPath)
    {
        var pathValue = Environment.GetEnvironmentVariable("PATH");
        if (string.IsNullOrWhiteSpace(pathValue))
        {
            return null;
        }

        foreach (var rawDirectory in pathValue.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            var directory = rawDirectory.Trim();
            if (directory.Length == 0)
            {
                continue;
            }

            var candidate = Path.Combine(directory, binary);
            if (!File.Exists(candidate))
            {
                continue;
            }

            var resolvedCandidate = Path.GetFullPath(candidate);
            if (IsShimPath(resolvedCandidate, shimRoot))
            {
                continue;
            }

            if (PointsToPath(resolvedCandidate, caiPath))
            {
                continue;
            }

            return resolvedCandidate;
        }

        return null;
    }

    private static bool IsShimPath(string candidate, string shimRoot)
    {
        if (string.Equals(candidate, shimRoot, StringComparison.Ordinal))
        {
            return true;
        }

        return candidate.StartsWith(shimRoot + Path.DirectorySeparatorChar, StringComparison.Ordinal);
    }

    private static bool PointsToPath(string path, string expectedPath)
    {
        if (string.Equals(path, expectedPath, StringComparison.Ordinal))
        {
            return true;
        }

        var info = new FileInfo(path);
        if (string.IsNullOrWhiteSpace(info.LinkTarget))
        {
            return false;
        }

        var linkTarget = info.LinkTarget;
        var resolved = Path.IsPathRooted(linkTarget)
            ? Path.GetFullPath(linkTarget)
            : Path.GetFullPath(Path.Combine(Path.GetDirectoryName(path) ?? "/", linkTarget));
        return string.Equals(resolved, expectedPath, StringComparison.Ordinal);
    }
}
