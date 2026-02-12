namespace ContainAI.Cli.Host;

internal interface ICaiUpdateDryRunReporter
{
    Task<int> RunUpdateDryRunAsync(bool stopContainers, bool limaRecreate);
}
