namespace ContainAI.Cli.Host.AgentShims;

internal sealed class AgentShimBinaryResolver : IAgentShimBinaryResolver
{
    public string ResolveCurrentExecutablePath()
    {
        var processPath = Environment.ProcessPath;
        if (!string.IsNullOrWhiteSpace(processPath))
        {
            return Path.GetFullPath(processPath);
        }

        var argv0 = Environment.GetCommandLineArgs().FirstOrDefault();
        if (string.IsNullOrWhiteSpace(argv0))
        {
            return string.Empty;
        }

        return Path.GetFullPath(argv0);
    }

    public string[] ResolveShimDirectories()
    {
        var installRoot = InstallMetadata.ResolveInstallDirectory();
        var values = new List<string>
        {
            "/opt/containai/agent-shims",
            "/opt/containai/user-agent-shims",
        };

        if (!string.IsNullOrWhiteSpace(installRoot))
        {
            values.Add(Path.Combine(installRoot, "agent-shims"));
            values.Add(Path.Combine(installRoot, "user-agent-shims"));
        }

        return values
            .Select(Path.GetFullPath)
            .Distinct(StringComparer.Ordinal)
            .ToArray();
    }

    public string? ResolveBinaryPath(string binary, IReadOnlyList<string> shimDirectories, string currentExecutablePath)
    {
        var pathValue = Environment.GetEnvironmentVariable("PATH");
        if (string.IsNullOrWhiteSpace(pathValue))
        {
            return null;
        }

        foreach (var rawDirectory in pathValue.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            if (string.IsNullOrWhiteSpace(rawDirectory))
            {
                continue;
            }

            var candidate = Path.Combine(rawDirectory, binary);
            if (!File.Exists(candidate))
            {
                continue;
            }

            var resolvedCandidate = Path.GetFullPath(candidate);
            if (IsInShimDirectory(resolvedCandidate, shimDirectories))
            {
                continue;
            }

            if (PointsToPath(resolvedCandidate, currentExecutablePath))
            {
                continue;
            }

            return resolvedCandidate;
        }

        return null;
    }

    private static bool IsInShimDirectory(string candidate, IReadOnlyList<string> shimDirectories)
    {
        foreach (var shimDirectory in shimDirectories)
        {
            if (string.Equals(candidate, shimDirectory, StringComparison.Ordinal))
            {
                return true;
            }

            if (candidate.StartsWith(shimDirectory + Path.DirectorySeparatorChar, StringComparison.Ordinal))
            {
                return true;
            }
        }

        return false;
    }

    private static bool PointsToPath(string path, string expectedPath)
    {
        if (string.IsNullOrWhiteSpace(expectedPath))
        {
            return false;
        }

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
