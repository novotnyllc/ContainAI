namespace ContainAI.Cli.Host;

internal sealed partial class DevcontainerFeatureInitLinkApplier
{
    private static string ResolveSourceHome(string? homeDirectory)
        => string.IsNullOrWhiteSpace(homeDirectory) ? "/home/agent" : homeDirectory;

    private static bool HasRequiredPaths(LinkEntry? link)
        => link is { Link: { } linkPath, Target: { } targetPath }
            && !string.IsNullOrWhiteSpace(linkPath)
            && !string.IsNullOrWhiteSpace(targetPath);

    private static bool ShouldSkipCredentialLink(LinkEntry link, bool enableCredentials)
        => !enableCredentials && DevcontainerFeaturePaths.CredentialTargets.Contains(link.Target);

    private static bool TargetExists(string target)
        => File.Exists(target) || Directory.Exists(target);

    private static string RewriteLinkPath(string linkPath, string sourceHome, string userHome)
        => linkPath.StartsWith(sourceHome, StringComparison.Ordinal)
            ? userHome + linkPath[sourceHome.Length..]
            : linkPath;

    private static void EnsureParentDirectoryExists(string rewrittenLink)
    {
        var parentDirectory = Path.GetDirectoryName(rewrittenLink);
        if (!string.IsNullOrWhiteSpace(parentDirectory))
        {
            Directory.CreateDirectory(parentDirectory);
        }
    }
}
