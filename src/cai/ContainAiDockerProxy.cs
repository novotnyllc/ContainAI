namespace ContainAI.Cli.Host;

internal static class ContainAiDockerProxy
{
    public static Task<int> RunAsync(IReadOnlyList<string> args, TextWriter stdout, TextWriter stderr, CancellationToken cancellationToken)
        => CreateDefaultService().RunAsync(args, stdout, stderr, cancellationToken);

    internal static string StripJsoncComments(string content)
        => CreateFeatureSettingsParser().StripJsoncComments(content);

    internal static (string? ConfigFile, string? LocalFolder) ExtractDevcontainerLabels(IReadOnlyList<string> args)
    {
        var labels = CreateArgumentParser().ExtractDevcontainerLabels(args);
        return (labels.ConfigFile, labels.LocalFolder);
    }

    internal static bool IsContainerCreateCommand(IReadOnlyList<string> args)
        => CreateArgumentParser().IsContainerCreateCommand(args);

    internal static string SanitizeWorkspaceName(string value)
        => CreateArgumentParser().SanitizeWorkspaceName(value);

    internal static bool TryReadFeatureSettings(string configFile, TextWriter stderr, out FeatureSettings settings)
        => CreateFeatureSettingsParser().TryReadFeatureSettings(configFile, stderr, out settings);

    internal static bool IsValidVolumeName(string volume)
        => CreateFeatureSettingsParser().IsValidVolumeName(volume);

    private static ContainAiDockerProxyService CreateDefaultService()
    {
        var options = ContainAiDockerProxyOptions.Default;
        var argumentParser = CreateArgumentParser();
        var featureSettingsParser = CreateFeatureSettingsParser(options);
        var processRunner = new DockerProxyProcessRunner();
        var systemEnvironment = new ContainAiSystemEnvironment();
        var clock = new SystemUtcClock();

        return new ContainAiDockerProxyService(
            options,
            argumentParser,
            featureSettingsParser,
            processRunner,
            systemEnvironment,
            clock);
    }

    private static DockerProxyArgumentParser CreateArgumentParser() => new();

    private static DevcontainerFeatureSettingsParser CreateFeatureSettingsParser()
        => CreateFeatureSettingsParser(ContainAiDockerProxyOptions.Default);

    private static DevcontainerFeatureSettingsParser CreateFeatureSettingsParser(ContainAiDockerProxyOptions options)
        => new(options);
}
