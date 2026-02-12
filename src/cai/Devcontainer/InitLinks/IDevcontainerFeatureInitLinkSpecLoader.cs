namespace ContainAI.Cli.Host.Devcontainer.InitLinks;

internal interface IDevcontainerFeatureInitLinkSpecLoader
{
    Task<LinkSpecDocument?> LoadLinkSpecForInitAsync(CancellationToken cancellationToken);
}
