namespace ContainAI.Cli.Host;

internal sealed class DevcontainerFeatureSettingsParser : IDevcontainerFeatureSettingsParser
{
    private readonly ContainAiDockerProxyOptions options;

    public DevcontainerFeatureSettingsParser(ContainAiDockerProxyOptions options) => this.options = options;

    public string StripJsoncComments(string content) => DockerProxyFeatureSettingsParsing.StripJsoncComments(content);

    public bool TryReadFeatureSettings(string configFile, TextWriter stderr, out FeatureSettings settings)
        => DockerProxyFeatureSettingsParsing.TryReadFeatureSettings(configFile, stderr, options, out settings);

    public bool IsValidVolumeName(string volume) => DockerProxyValidationHelpers.IsValidVolumeName(volume);
}
