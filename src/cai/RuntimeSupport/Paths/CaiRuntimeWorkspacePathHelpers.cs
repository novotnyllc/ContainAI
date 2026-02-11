namespace ContainAI.Cli.Host.RuntimeSupport.Paths;

internal static class CaiRuntimeWorkspacePathHelpers
{
    internal static string? TryFindWorkspaceConfigPath(string? workspacePath, IReadOnlyList<string> configFileNames)
    {
        var normalizedStart = ResolveWorkspaceSearchStartPath(workspacePath);
        var current = File.Exists(normalizedStart)
            ? Path.GetDirectoryName(normalizedStart)
            : normalizedStart;

        while (!string.IsNullOrWhiteSpace(current))
        {
            foreach (var fileName in configFileNames)
            {
                var candidate = Path.Combine(current, ".containai", fileName);
                if (File.Exists(candidate))
                {
                    return candidate;
                }
            }

            var parent = Directory.GetParent(current);
            if (parent is null || string.Equals(parent.FullName, current, StringComparison.Ordinal))
            {
                break;
            }

            current = parent.FullName;
        }

        return null;
    }

    internal static string CanonicalizeWorkspacePath(string workspacePath)
        => Path.GetFullPath(CaiRuntimeHomePathHelpers.ExpandHomePath(workspacePath));

    private static string ResolveWorkspaceSearchStartPath(string? workspacePath)
    {
        var startPath = string.IsNullOrWhiteSpace(workspacePath)
            ? Directory.GetCurrentDirectory()
            : CaiRuntimeHomePathHelpers.ExpandHomePath(workspacePath);

        return Path.GetFullPath(startPath);
    }
}
