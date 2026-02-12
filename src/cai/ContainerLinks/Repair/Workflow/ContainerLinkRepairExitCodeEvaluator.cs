namespace ContainAI.Cli.Host;

internal sealed class ContainerLinkRepairExitCodeEvaluator : IContainerLinkRepairExitCodeEvaluator
{
    public int Evaluate(ContainerLinkRepairMode mode, ContainerLinkRepairStats stats)
    {
        ArgumentNullException.ThrowIfNull(stats);

        if (stats.Errors > 0)
        {
            return 1;
        }

        return mode == ContainerLinkRepairMode.Check && (stats.Broken + stats.Missing) > 0
            ? 1
            : 0;
    }
}
