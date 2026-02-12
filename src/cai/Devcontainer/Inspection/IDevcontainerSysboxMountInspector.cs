namespace ContainAI.Cli.Host.Devcontainer.Inspection;

internal interface IDevcontainerSysboxMountInspector
{
    Task<bool> IsSysboxFsMountedAsync(CancellationToken cancellationToken);
}
