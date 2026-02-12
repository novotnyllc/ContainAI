namespace ContainAI.Cli.Host.Devcontainer.InitLinks;

internal static class DevcontainerFeatureLinkFilter
{
    public static bool HasRequiredPaths(LinkEntry? link)
        => link is { Link: { } linkPath, Target: { } targetPath }
            && !string.IsNullOrWhiteSpace(linkPath)
            && !string.IsNullOrWhiteSpace(targetPath);

    public static bool ShouldSkipCredentialLink(LinkEntry link, bool enableCredentials)
        => !enableCredentials && DevcontainerFeaturePaths.CredentialTargets.Contains(link.Target);

    public static bool TargetExists(string target)
        => File.Exists(target) || Directory.Exists(target);
}
