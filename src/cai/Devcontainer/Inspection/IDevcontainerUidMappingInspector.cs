namespace ContainAI.Cli.Host.Devcontainer.Inspection;

internal interface IDevcontainerUidMappingInspector
{
    Task<bool> HasUidMappingIsolationAsync(CancellationToken cancellationToken);
}
