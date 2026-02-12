using System.ComponentModel;

namespace ContainAI.Cli.Host;

internal interface IContainerLinkEntryStateReporter
{
    Task<bool> ReportAndDetermineRepairAsync(
        ContainerLinkSpecEntry entry,
        ContainerLinkEntryState state,
        bool quiet,
        ContainerLinkRepairStats stats);
}
