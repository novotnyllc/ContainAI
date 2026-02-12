namespace ContainAI.Cli.Host;

internal interface IContainerLinkRepairExitCodeEvaluator
{
    int Evaluate(ContainerLinkRepairMode mode, ContainerLinkRepairStats stats);
}
