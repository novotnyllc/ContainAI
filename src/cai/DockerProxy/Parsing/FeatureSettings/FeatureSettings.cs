using ContainAI.Cli.Host.DockerProxy.Models;

namespace ContainAI.Cli.Host.DockerProxy.Parsing.Settings;

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
