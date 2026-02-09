using System.Text.RegularExpressions;

namespace ContainAI.Cli.Host;

internal static partial class ManifestApplier
{
    private static readonly Regex CommandNameRegex = CommandNameRegexFactory();

    public static int ApplyAgentShims(string manifestPath, string shimDirectory, string caiExecutablePath)
        => ApplyAgentShims(manifestPath, shimDirectory, caiExecutablePath, new ManifestTomlParser());

    public static int ApplyAgentShims(
        string manifestPath,
        string shimDirectory,
        string caiExecutablePath,
        IManifestTomlParser manifestTomlParser)
    {
        ArgumentNullException.ThrowIfNull(manifestTomlParser);

        if (!Path.IsPathRooted(shimDirectory))
        {
            throw new InvalidOperationException($"shim directory must be absolute: {shimDirectory}");
        }

        if (!Path.IsPathRooted(caiExecutablePath))
        {
            throw new InvalidOperationException($"cai executable path must be absolute: {caiExecutablePath}");
        }

        var shimRoot = Path.GetFullPath(shimDirectory);
        var caiPath = Path.GetFullPath(caiExecutablePath);
        Directory.CreateDirectory(shimRoot);

        var agents = manifestTomlParser.ParseAgents(manifestPath);
        var applied = 0;

        foreach (var agent in agents)
        {
            var resolvedBinary = ResolveBinaryPath(agent.Binary, shimRoot, caiPath);
            if (agent.Optional && resolvedBinary is null)
            {
                continue;
            }

            var names = new HashSet<string>(StringComparer.Ordinal)
            {
                agent.Name,
                agent.Binary,
            };

            foreach (var alias in agent.Aliases)
            {
                names.Add(alias);
            }

            foreach (var commandName in names)
            {
                ValidateCommandName(commandName, agent.SourceFile);
                var shimPath = Path.Combine(shimRoot, commandName);
                if (EnsureShimLink(shimPath, caiPath))
                {
                    applied++;
                }
            }
        }

        return applied;
    }

    private static void ValidateCommandName(string commandName, string sourceFile)
    {
        if (!CommandNameRegex.IsMatch(commandName))
        {
            throw new InvalidOperationException($"invalid agent command name '{commandName}' in {sourceFile}");
        }
    }

    private static bool EnsureShimLink(string shimPath, string caiPath)
    {
        var parent = Path.GetDirectoryName(shimPath);
        if (!string.IsNullOrWhiteSpace(parent))
        {
            Directory.CreateDirectory(parent);
        }

        if (IsSymbolicLink(shimPath))
        {
            var currentTarget = ResolveLinkTarget(shimPath);
            if (string.Equals(currentTarget, caiPath, StringComparison.Ordinal))
            {
                return false;
            }

            RemovePath(shimPath);
        }
        else if (File.Exists(shimPath) || Directory.Exists(shimPath))
        {
            // Never overwrite non-symlink paths.
            return false;
        }

        File.CreateSymbolicLink(shimPath, caiPath);
        return true;
    }

    private static string? ResolveBinaryPath(string binary, string shimRoot, string caiPath)
    {
        var pathValue = Environment.GetEnvironmentVariable("PATH");
        if (string.IsNullOrWhiteSpace(pathValue))
        {
            return null;
        }

        var separator = Path.PathSeparator;
        foreach (var rawDirectory in pathValue.Split(separator, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
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

    [GeneratedRegex("^[A-Za-z0-9][A-Za-z0-9._-]*$", RegexOptions.CultureInvariant)]
    private static partial Regex CommandNameRegexFactory();
}
