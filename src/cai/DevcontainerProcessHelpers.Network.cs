namespace ContainAI.Cli.Host;

internal sealed partial class DevcontainerProcessHelpers
{
    public bool IsPortInUse(string portValue)
    {
        if (!int.TryParse(portValue, out var port))
        {
            return false;
        }

        return portInspector.IsPortInUse(port);
    }
}
