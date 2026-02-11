namespace ContainAI.Cli.Host;

internal static class DevcontainerFeatureLinkPathResolver
{
    public static string ResolveSourceHome(string? homeDirectory)
        => string.IsNullOrWhiteSpace(homeDirectory) ? "/home/agent" : homeDirectory;

    public static string RewriteLinkPath(string linkPath, string sourceHome, string userHome)
        => linkPath.StartsWith(sourceHome, StringComparison.Ordinal)
            ? userHome + linkPath[sourceHome.Length..]
            : linkPath;

    public static void EnsureParentDirectoryExists(string rewrittenLink)
    {
        var parentDirectory = Path.GetDirectoryName(rewrittenLink);
        if (!string.IsNullOrWhiteSpace(parentDirectory))
        {
            Directory.CreateDirectory(parentDirectory);
        }
    }
}
