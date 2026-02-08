using System.Runtime.InteropServices;
using System.Text.RegularExpressions;

namespace ContainAI.Cli.Host;

internal static partial class ManifestApplier
{
    private static readonly Regex CommandNameRegex = CommandNameRegexFactory();

    public static int ApplyContainerLinks(string manifestPath, string homeDirectory, string dataDirectory)
    {
        var homeRoot = Path.GetFullPath(homeDirectory);
        var dataRoot = Path.GetFullPath(dataDirectory);

        var entries = ManifestTomlParser.Parse(manifestPath, includeDisabled: true, includeSourceFile: false)
            .Where(static entry => !string.IsNullOrWhiteSpace(entry.ContainerLink))
            .Where(static entry => !entry.Flags.Contains('G', StringComparison.Ordinal))
            .ToArray();

        var applied = 0;
        foreach (var entry in entries)
        {
            var linkPath = CombineUnderRoot(homeRoot, entry.ContainerLink, "container_link");
            var targetPath = CombineUnderRoot(dataRoot, entry.Target, "target");
            ApplyLink(linkPath, targetPath, entry.Flags.Contains('R', StringComparison.Ordinal));
            applied++;
        }

        return applied;
    }

    public static int ApplyInitDirs(string manifestPath, string dataDirectory)
    {
        var dataRoot = Path.GetFullPath(dataDirectory);
        Directory.CreateDirectory(dataRoot);

        var parsed = ManifestTomlParser.Parse(manifestPath, includeDisabled: true, includeSourceFile: false);
        var applied = 0;

        foreach (var entry in parsed.Where(static entry => string.Equals(entry.Type, "entry", StringComparison.Ordinal)))
        {
            if (string.IsNullOrWhiteSpace(entry.Target) || entry.Flags.Contains('G', StringComparison.Ordinal))
            {
                continue;
            }

            if (entry.Flags.Contains('f', StringComparison.Ordinal) && string.IsNullOrWhiteSpace(entry.ContainerLink))
            {
                continue;
            }

            var fullPath = CombineUnderRoot(dataRoot, entry.Target, "target");
            if (entry.Flags.Contains('d', StringComparison.Ordinal))
            {
                EnsureDirectory(fullPath);
                if (entry.Flags.Contains('s', StringComparison.Ordinal))
                {
                    SetUnixModeIfSupported(fullPath, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
                }

                applied++;
                continue;
            }

            if (!entry.Flags.Contains('f', StringComparison.Ordinal))
            {
                continue;
            }

            EnsureFile(fullPath, initializeJson: entry.Flags.Contains('j', StringComparison.Ordinal));
            if (entry.Flags.Contains('s', StringComparison.Ordinal))
            {
                SetUnixModeIfSupported(fullPath, UnixFileMode.UserRead | UnixFileMode.UserWrite);
            }

            applied++;
        }

        foreach (var entry in parsed.Where(static entry => string.Equals(entry.Type, "symlink", StringComparison.Ordinal)))
        {
            if (string.IsNullOrWhiteSpace(entry.Target) || !entry.Flags.Contains('f', StringComparison.Ordinal))
            {
                continue;
            }

            var fullPath = CombineUnderRoot(dataRoot, entry.Target, "target");
            EnsureFile(fullPath, initializeJson: entry.Flags.Contains('j', StringComparison.Ordinal));
            applied++;
        }

        return applied;
    }

    public static int ApplyAgentShims(string manifestPath, string shimDirectory, string caiExecutablePath)
    {
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

        var agents = ManifestTomlParser.ParseAgents(manifestPath);
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

    private static void ApplyLink(string linkPath, string targetPath, bool removeFirst)
    {
        var parent = Path.GetDirectoryName(linkPath);
        if (!string.IsNullOrWhiteSpace(parent))
        {
            Directory.CreateDirectory(parent);
        }

        if (IsSymbolicLink(linkPath))
        {
            var currentTarget = ResolveLinkTarget(linkPath);
            if (string.Equals(currentTarget, targetPath, StringComparison.Ordinal))
            {
                return;
            }

            File.Delete(linkPath);
        }
        else if (Directory.Exists(linkPath))
        {
            if (!removeFirst)
            {
                throw new InvalidOperationException($"cannot replace directory without R flag: {linkPath}");
            }

            Directory.Delete(linkPath, recursive: true);
        }
        else if (File.Exists(linkPath))
        {
            File.Delete(linkPath);
        }

        File.CreateSymbolicLink(linkPath, targetPath);
    }

    private static void EnsureDirectory(string path)
    {
        RejectSymlink(path);
        if (File.Exists(path))
        {
            throw new InvalidOperationException($"expected directory but found file: {path}");
        }

        Directory.CreateDirectory(path);
    }

    private static void EnsureFile(string path, bool initializeJson)
    {
        RejectSymlink(path);

        var directory = Path.GetDirectoryName(path);
        if (!string.IsNullOrWhiteSpace(directory))
        {
            EnsureDirectory(directory);
        }

        if (Directory.Exists(path))
        {
            throw new InvalidOperationException($"expected file but found directory: {path}");
        }

        using (File.Open(path, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.Read))
        {
        }

        if (initializeJson)
        {
            var info = new FileInfo(path);
            if (info.Length == 0)
            {
                File.WriteAllText(path, "{}");
            }
        }
    }

    private static void SetUnixModeIfSupported(string path, UnixFileMode mode)
    {
        if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
        {
            return;
        }

        File.SetUnixFileMode(path, mode);
    }

    private static string CombineUnderRoot(string root, string relativePath, string fieldName)
    {
        if (Path.IsPathRooted(relativePath))
        {
            throw new InvalidOperationException($"{fieldName} must be relative: {relativePath}");
        }

        var combined = Path.GetFullPath(Path.Combine(root, relativePath));
        if (string.Equals(combined, root, StringComparison.Ordinal))
        {
            return combined;
        }

        if (!combined.StartsWith(root + Path.DirectorySeparatorChar, StringComparison.Ordinal))
        {
            throw new InvalidOperationException($"{fieldName} escapes root: {relativePath}");
        }

        return combined;
    }

    private static bool IsSymbolicLink(string path)
    {
        if (!File.Exists(path) && !Directory.Exists(path))
        {
            return false;
        }

        return (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0;
    }

    private static string? ResolveLinkTarget(string path)
    {
        var info = new FileInfo(path);
        if (string.IsNullOrWhiteSpace(info.LinkTarget))
        {
            return null;
        }

        return Path.IsPathRooted(info.LinkTarget)
            ? Path.GetFullPath(info.LinkTarget)
            : Path.GetFullPath(Path.Combine(Path.GetDirectoryName(path) ?? "/", info.LinkTarget));
    }

    private static void RejectSymlink(string path)
    {
        if (!IsSymbolicLink(path))
        {
            return;
        }

        throw new InvalidOperationException($"symlink is not allowed for this operation: {path}");
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

    private static void RemovePath(string path)
    {
        if (Directory.Exists(path) && !File.Exists(path))
        {
            Directory.Delete(path, recursive: false);
            return;
        }

        if (File.Exists(path))
        {
            File.Delete(path);
        }
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
