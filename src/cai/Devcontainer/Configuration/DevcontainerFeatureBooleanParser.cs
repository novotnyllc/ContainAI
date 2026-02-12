namespace ContainAI.Cli.Host.Devcontainer.Configuration;

internal sealed class DevcontainerFeatureBooleanParser(
    Func<string, string?> environmentVariableReader) : IDevcontainerFeatureBooleanParser
{
    public bool TryParse(string name, bool defaultValue, out bool value, out string error)
    {
        var rawValue = environmentVariableReader(name);
        if (string.IsNullOrWhiteSpace(rawValue))
        {
            value = defaultValue;
            error = string.Empty;
            return true;
        }

        switch (rawValue.Trim())
        {
            case "true":
            case "TRUE":
            case "True":
            case "1":
                value = true;
                error = string.Empty;
                return true;
            case "false":
            case "FALSE":
            case "False":
            case "0":
                value = false;
                error = string.Empty;
                return true;
            default:
                value = defaultValue;
                error = $"ERROR: Invalid {name} \"{rawValue}\". Must be true or false.";
                return false;
        }
    }
}
