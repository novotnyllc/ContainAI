using System.Security;

namespace ContainAI.Cli.Host;

internal static partial class SessionRuntimeInfrastructure
{
    public static string ResolveHostTimeZone()
    {
        try
        {
            return TimeZoneInfo.Local.Id;
        }
        catch (TimeZoneNotFoundException)
        {
            return "UTC";
        }
        catch (InvalidTimeZoneException)
        {
            return "UTC";
        }
        catch (SecurityException)
        {
            return "UTC";
        }
    }

    public static void ParsePortsFromSocketTable(string content, HashSet<int> destination)
    {
        foreach (var line in content.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            var parts = line.Split(' ', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
            if (parts.Length < 4)
            {
                continue;
            }

            var endpoint = parts[3];
            var separator = endpoint.LastIndexOf(':');
            if (separator <= 0 || separator >= endpoint.Length - 1)
            {
                continue;
            }

            if (int.TryParse(endpoint[(separator + 1)..], out var port) && port > 0)
            {
                destination.Add(port);
            }
        }
    }
}
