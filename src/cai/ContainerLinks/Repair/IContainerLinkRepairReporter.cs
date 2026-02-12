namespace ContainAI.Cli.Host;

internal interface IContainerLinkRepairReporter
{
    Task LogInfoAsync(bool quiet, string message);

    Task WriteSummaryAsync(ContainerLinkRepairMode mode, ContainerLinkRepairStats stats, bool quiet);
}
