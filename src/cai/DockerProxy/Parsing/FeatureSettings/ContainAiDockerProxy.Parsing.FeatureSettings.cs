namespace ContainAI.Cli.Host;

internal static class DockerProxyFeatureSettingsParsing
{
    public static string StripJsoncComments(string content)
        => DockerProxyJsoncCommentStripper.Strip(content);

    public static bool TryReadFeatureSettings(
        string configFile,
        TextWriter stderr,
        ContainAiDockerProxyOptions options,
        out FeatureSettings settings)
        => DockerProxyFeatureSettingsReader.TryReadFeatureSettings(configFile, stderr, options, out settings);
}
