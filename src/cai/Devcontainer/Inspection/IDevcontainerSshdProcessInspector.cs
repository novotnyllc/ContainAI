namespace ContainAI.Cli.Host.Devcontainer.Inspection;

internal interface IDevcontainerSshdProcessInspector
{
    Task<bool> IsSshdRunningFromPidFileAsync(string pidFilePath, CancellationToken cancellationToken);
}
