namespace ContainAI.Cli.Host;

internal interface IDevcontainerFeatureInitLinkApplier
{
    Task<DevcontainerFeatureLinkApplyResult> ApplyLinksAsync(
        LinkSpecDocument linkSpec,
        FeatureConfig settings,
        string userHome,
        CancellationToken cancellationToken);
}

internal readonly record struct DevcontainerFeatureLinkApplyResult(int Created, int Skipped);

internal sealed class DevcontainerFeatureInitLinkApplier : IDevcontainerFeatureInitLinkApplier
{
    private readonly TextWriter stdout;
    private readonly TextWriter stderr;
    private readonly IDevcontainerProcessHelpers processHelpers;

    public DevcontainerFeatureInitLinkApplier(
        TextWriter stdout,
        TextWriter stderr,
        IDevcontainerProcessHelpers processHelpers)
    {
        this.stdout = stdout ?? throw new ArgumentNullException(nameof(stdout));
        this.stderr = stderr ?? throw new ArgumentNullException(nameof(stderr));
        this.processHelpers = processHelpers ?? throw new ArgumentNullException(nameof(processHelpers));
    }

    public async Task<DevcontainerFeatureLinkApplyResult> ApplyLinksAsync(
        LinkSpecDocument linkSpec,
        FeatureConfig settings,
        string userHome,
        CancellationToken cancellationToken)
    {
        var created = 0;
        var skipped = 0;
        var sourceHome = ResolveSourceHome(linkSpec.HomeDirectory);
        foreach (var link in linkSpec.Links ?? [])
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (!HasRequiredPaths(link))
            {
                continue;
            }

            if (ShouldSkipCredentialLink(link, settings.EnableCredentials))
            {
                await stdout.WriteLineAsync($"  [SKIP] {link.Link} (credentials disabled)").ConfigureAwait(false);
                skipped++;
                continue;
            }

            if (!TargetExists(link.Target))
            {
                continue;
            }

            var rewrittenLink = RewriteLinkPath(link.Link, sourceHome, userHome);
            EnsureParentDirectoryExists(rewrittenLink);

            var removeFirst = link.RemoveFirst ?? false;
            var prepared = await PrepareDestinationAsync(rewrittenLink, removeFirst).ConfigureAwait(false);
            if (!prepared)
            {
                continue;
            }

            CreateSymbolicLink(rewrittenLink, link.Target);

            await stdout.WriteLineAsync($"  [OK] {rewrittenLink} -> {link.Target}").ConfigureAwait(false);
            created++;
        }

        return new DevcontainerFeatureLinkApplyResult(created, skipped);
    }

    private async Task<bool> PrepareDestinationAsync(string rewrittenLink, bool removeFirst)
    {
        if (Directory.Exists(rewrittenLink) && !processHelpers.IsSymlink(rewrittenLink))
        {
            if (!removeFirst)
            {
                await stderr.WriteLineAsync($"  [FAIL] {rewrittenLink} (directory exists, remove_first not set)").ConfigureAwait(false);
                return false;
            }

            Directory.Delete(rewrittenLink, recursive: true);
        }
        else if (File.Exists(rewrittenLink) || processHelpers.IsSymlink(rewrittenLink))
        {
            File.Delete(rewrittenLink);
        }

        return true;
    }

    private static void CreateSymbolicLink(string rewrittenLink, string target)
    {
        if (Directory.Exists(target))
        {
            Directory.CreateSymbolicLink(rewrittenLink, target);
        }
        else
        {
            File.CreateSymbolicLink(rewrittenLink, target);
        }
    }

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
