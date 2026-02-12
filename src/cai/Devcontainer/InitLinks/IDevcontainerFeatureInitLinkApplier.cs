namespace ContainAI.Cli.Host.Devcontainer.InitLinks;

internal interface IDevcontainerFeatureInitLinkApplier
{
    Task<DevcontainerFeatureLinkApplyResult> ApplyLinksAsync(
        LinkSpecDocument linkSpec,
        FeatureConfig settings,
        string userHome,
        CancellationToken cancellationToken);
}
