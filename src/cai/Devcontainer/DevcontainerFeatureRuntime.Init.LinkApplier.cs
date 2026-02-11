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

internal sealed partial class DevcontainerFeatureInitLinkApplier : IDevcontainerFeatureInitLinkApplier
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
}
