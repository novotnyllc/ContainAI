namespace ContainAI.Cli.Host;

internal abstract partial class CaiRuntimeSupport
{
    protected static string? TryFindWorkspaceConfigPath(string? workspacePath)
    {
        var normalizedStart = ResolveWorkspaceSearchStartPath(workspacePath);
        var current = File.Exists(normalizedStart)
            ? Path.GetDirectoryName(normalizedStart)
            : normalizedStart;

        while (!string.IsNullOrWhiteSpace(current))
        {
            foreach (var fileName in ConfigFileNames)
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

    private static string ResolveWorkspaceSearchStartPath(string? workspacePath)
    {
        var startPath = string.IsNullOrWhiteSpace(workspacePath)
            ? Directory.GetCurrentDirectory()
            : ExpandHomePath(workspacePath);

        return Path.GetFullPath(startPath);
    }

    private static string CanonicalizeWorkspacePath(string workspacePath) => Path.GetFullPath(ExpandHomePath(workspacePath));
}
