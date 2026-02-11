using System.Globalization;

namespace ContainAI.Cli.Host;

internal static class TomlCommandValueFormatter
{
    private static readonly HashSet<string> PortKeys =
    [
        "port_range_start",
        "port_range_end",
        "ssh.port_range_start",
        "ssh.port_range_end",
    ];

    private static readonly HashSet<string> BoolKeys =
    [
        "forward_agent",
        "auto_prompt",
        "exclude_priv",
        "ssh.forward_agent",
        "import.auto_prompt",
        "import.exclude_priv",
    ];

    public static string? FormatTomlValueForKey(string key, string value)
    {
        var keyName = key.Contains('.', StringComparison.Ordinal)
            ? key[(key.LastIndexOf('.') + 1)..]
            : key;

        if (PortKeys.Contains(key) || PortKeys.Contains(keyName))
        {
            if (!int.TryParse(value, NumberStyles.Integer, CultureInfo.InvariantCulture, out var port))
            {
                return null;
            }

            if (port is < 1024 or > 65535)
            {
                return null;
            }

            return port.ToString(CultureInfo.InvariantCulture);
        }

        if (BoolKeys.Contains(key) || BoolKeys.Contains(keyName))
        {
            return value.ToLowerInvariant() switch
            {
                "true" or "1" or "yes" => "true",
                "false" or "0" or "no" => "false",
                _ => null,
            };
        }

        return TomlCommandTextFormatter.FormatTomlString(value);
    }
}
