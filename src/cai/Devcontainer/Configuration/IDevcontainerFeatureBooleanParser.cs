namespace ContainAI.Cli.Host.Devcontainer.Configuration;

internal interface IDevcontainerFeatureBooleanParser
{
    bool TryParse(string name, bool defaultValue, out bool value, out string error);
}
