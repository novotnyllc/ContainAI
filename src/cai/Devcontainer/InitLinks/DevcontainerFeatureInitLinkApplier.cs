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
    private readonly DevcontainerFeatureLinkDestinationPreparer destinationPreparer;

    public DevcontainerFeatureInitLinkApplier(
        TextWriter stdout,
        TextWriter stderr,
        IDevcontainerProcessHelpers processHelpers)
    {
        this.stdout = stdout ?? throw new ArgumentNullException(nameof(stdout));
        destinationPreparer = new DevcontainerFeatureLinkDestinationPreparer(
            stderr ?? throw new ArgumentNullException(nameof(stderr)),
            processHelpers ?? throw new ArgumentNullException(nameof(processHelpers)));
    }

    public async Task<DevcontainerFeatureLinkApplyResult> ApplyLinksAsync(
        LinkSpecDocument linkSpec,
        FeatureConfig settings,
        string userHome,
        CancellationToken cancellationToken)
    {
        var created = 0;
        var skipped = 0;
        var sourceHome = DevcontainerFeatureLinkPathResolver.ResolveSourceHome(linkSpec.HomeDirectory);

        foreach (var link in linkSpec.Links ?? [])
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (!DevcontainerFeatureLinkFilter.HasRequiredPaths(link))
            {
                continue;
            }

            if (DevcontainerFeatureLinkFilter.ShouldSkipCredentialLink(link, settings.EnableCredentials))
            {
                await stdout.WriteLineAsync($"  [SKIP] {link.Link} (credentials disabled)").ConfigureAwait(false);
                skipped++;
                continue;
            }

            if (!DevcontainerFeatureLinkFilter.TargetExists(link.Target))
            {
                continue;
            }

            var rewrittenLink = DevcontainerFeatureLinkPathResolver.RewriteLinkPath(link.Link, sourceHome, userHome);
            DevcontainerFeatureLinkPathResolver.EnsureParentDirectoryExists(rewrittenLink);

            var removeFirst = link.RemoveFirst ?? false;
            var prepared = await destinationPreparer.PrepareDestinationAsync(rewrittenLink, removeFirst).ConfigureAwait(false);
            if (!prepared)
            {
                continue;
            }

            DevcontainerFeatureLinkDestinationPreparer.CreateSymbolicLink(rewrittenLink, link.Target);
            await stdout.WriteLineAsync($"  [OK] {rewrittenLink} -> {link.Target}").ConfigureAwait(false);
            created++;
        }

        return new DevcontainerFeatureLinkApplyResult(created, skipped);
    }
}
