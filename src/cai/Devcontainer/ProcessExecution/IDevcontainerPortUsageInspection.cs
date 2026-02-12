namespace ContainAI.Cli.Host.Devcontainer.ProcessExecution;

internal interface IDevcontainerPortUsageInspection
{
    bool IsPortInUse(string portValue);
}
