namespace ContainAI.Cli.Host.Devcontainer.ProcessExecution;

internal interface IDevcontainerProcessLivenessChecker
{
    bool IsProcessAlive(int processId);
}
