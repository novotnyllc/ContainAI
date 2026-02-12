namespace ContainAI.Cli.Host.Devcontainer.ProcessExecution;

internal sealed class DevcontainerPortUsageInspection : IDevcontainerPortUsageInspection
{
    private readonly DevcontainerPortInspector portInspector;

    public DevcontainerPortUsageInspection(DevcontainerPortInspector portInspector)
        => this.portInspector = portInspector ?? throw new ArgumentNullException(nameof(portInspector));

    public bool IsPortInUse(string portValue)
    {
        if (!int.TryParse(portValue, out var port))
        {
            return false;
        }

        return portInspector.IsPortInUse(port);
    }
}
