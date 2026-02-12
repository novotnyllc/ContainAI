namespace ContainAI.Cli.Host.Devcontainer.Configuration;

internal interface IDevcontainerFeatureConfigValidator
{
    bool Validate(FeatureConfig config, out string error);
}

internal sealed class DevcontainerFeatureConfigValidator : IDevcontainerFeatureConfigValidator
{
    public bool Validate(FeatureConfig config, out string error)
    {
        if (!DevcontainerFeatureValidationRegexes.VolumeNameRegex().IsMatch(config.DataVolume))
        {
            error = $"ERROR: Invalid dataVolume \"{config.DataVolume}\". Must be alphanumeric with ._- allowed.";
            return false;
        }

        if (!string.Equals(config.RemoteUser, "auto", StringComparison.Ordinal) &&
            !DevcontainerFeatureValidationRegexes.UnixUsernameRegex().IsMatch(config.RemoteUser))
        {
            error = $"ERROR: Invalid remoteUser \"{config.RemoteUser}\". Must be \"auto\" or a valid Unix username.";
            return false;
        }

        error = string.Empty;
        return true;
    }
}
