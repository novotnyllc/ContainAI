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
        var sourceHome = string.IsNullOrWhiteSpace(linkSpec.HomeDirectory) ? "/home/agent" : linkSpec.HomeDirectory!;
        foreach (var link in linkSpec.Links ?? [])
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (link is null || string.IsNullOrWhiteSpace(link.Link) || string.IsNullOrWhiteSpace(link.Target))
            {
                continue;
            }

            if (!settings.EnableCredentials && DevcontainerFeaturePaths.CredentialTargets.Contains(link.Target))
            {
                await stdout.WriteLineAsync($"  [SKIP] {link.Link} (credentials disabled)").ConfigureAwait(false);
                skipped++;
                continue;
            }

            if (!File.Exists(link.Target) && !Directory.Exists(link.Target))
            {
                continue;
            }

            var rewrittenLink = link.Link.StartsWith(sourceHome, StringComparison.Ordinal)
                ? userHome + link.Link[sourceHome.Length..]
                : link.Link;
            var parentDirectory = Path.GetDirectoryName(rewrittenLink);
            if (!string.IsNullOrWhiteSpace(parentDirectory))
            {
                Directory.CreateDirectory(parentDirectory);
            }

            var removeFirst = link.RemoveFirst ?? false;
            if (Directory.Exists(rewrittenLink) && !processHelpers.IsSymlink(rewrittenLink))
            {
                if (!removeFirst)
                {
                    await stderr.WriteLineAsync($"  [FAIL] {rewrittenLink} (directory exists, remove_first not set)").ConfigureAwait(false);
                    continue;
                }

                Directory.Delete(rewrittenLink, recursive: true);
            }
            else if (File.Exists(rewrittenLink) || processHelpers.IsSymlink(rewrittenLink))
            {
                File.Delete(rewrittenLink);
            }

            if (Directory.Exists(link.Target))
            {
                Directory.CreateSymbolicLink(rewrittenLink, link.Target);
            }
            else
            {
                File.CreateSymbolicLink(rewrittenLink, link.Target);
            }

            await stdout.WriteLineAsync($"  [OK] {rewrittenLink} -> {link.Target}").ConfigureAwait(false);
            created++;
        }

        return new DevcontainerFeatureLinkApplyResult(created, skipped);
    }
}
