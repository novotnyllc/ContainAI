using System.Net.NetworkInformation;

namespace ContainAI.Cli.Host;

internal sealed partial class DevcontainerFeatureRuntime
{
    private sealed partial class DevcontainerProcessHelpers
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

    private sealed class DevcontainerPortInspector
    {
        private readonly Func<IPGlobalProperties> ipGlobalPropertiesFactory;

        public DevcontainerPortInspector() => ipGlobalPropertiesFactory = IPGlobalProperties.GetIPGlobalProperties;

        public bool IsPortInUse(int port)
        {
            try
            {
                return ipGlobalPropertiesFactory()
                    .GetActiveTcpListeners()
                    .Any(endpoint => endpoint.Port == port);
            }
            catch (NetworkInformationException)
            {
                return false;
            }
            catch (InvalidOperationException)
            {
                return false;
            }
        }
    }
}
