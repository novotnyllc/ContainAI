using System.Net.NetworkInformation;

namespace ContainAI.Cli.Host;

internal sealed class ContainAiSystemEnvironment : IContainAiSystemEnvironment
{
    public string? GetEnvironmentVariable(string variableName) => Environment.GetEnvironmentVariable(variableName);

    public string ResolveHomeDirectory()
    {
        var home = Environment.GetEnvironmentVariable("HOME");
        return !string.IsNullOrWhiteSpace(home)
            ? home!
            : Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
    }

    public bool IsPortInUse(int port)
    {
        try
        {
            return IPGlobalProperties.GetIPGlobalProperties()
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
