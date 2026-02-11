namespace ContainAI.Cli.Host;

internal sealed partial class DevcontainerProcessHelpers
{
    public bool IsPortInUse(string portValue)
        => portUsageInspection.IsPortInUse(portValue);
}
