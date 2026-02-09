namespace ContainAI.Cli.Host;

internal static partial class AgentShimDispatcher
{
    private static ManifestAgentEntry? ResolveDefinition(IManifestTomlParser manifestTomlParser, string invocationName)
    {
        foreach (var manifestDirectory in ResolveManifestDirectories())
        {
            IReadOnlyList<ManifestAgentEntry> agents;
            try
            {
                agents = manifestTomlParser.ParseAgents(manifestDirectory);
            }
            catch (IOException)
            {
                continue;
            }
            catch (UnauthorizedAccessException)
            {
                continue;
            }
            catch (ArgumentException)
            {
                continue;
            }
            catch (InvalidOperationException)
            {
                continue;
            }

            foreach (var agent in agents)
            {
                if (MatchesInvocation(agent, invocationName))
                {
                    return agent;
                }
            }
        }

        return null;
    }

    private static bool MatchesInvocation(ManifestAgentEntry entry, string invocationName)
    {
        if (string.Equals(entry.Name, invocationName, StringComparison.Ordinal))
        {
            return true;
        }

        if (string.Equals(entry.Binary, invocationName, StringComparison.Ordinal))
        {
            return true;
        }

        return entry.Aliases.Any(alias => string.Equals(alias, invocationName, StringComparison.Ordinal));
    }

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

    private static string[] ResolveShimDirectories()
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

    private static string ResolveCurrentExecutablePath()
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

    private static string? ResolveBinaryPath(string binary, IReadOnlyList<string> shimDirectories, string currentExecutablePath)
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
