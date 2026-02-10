namespace ContainAI.Cli.Host;

internal interface IDockerProxyArgumentParser
{
    DockerProxyWrapperFlags ParseWrapperFlags(IReadOnlyList<string> args);

    DevcontainerLabels ExtractDevcontainerLabels(IReadOnlyList<string> args);

    bool IsContainerCreateCommand(IReadOnlyList<string> args);

    string SanitizeWorkspaceName(string value);

    string? GetFirstSubcommand(IReadOnlyList<string> args);

    string? GetContainerNameArg(IReadOnlyList<string> args, string subcommand);

    List<string> PrependContext(string contextName, IReadOnlyList<string> args);
}

internal interface IDevcontainerFeatureSettingsParser
{
    string StripJsoncComments(string content);

    bool TryReadFeatureSettings(string configFile, TextWriter stderr, out FeatureSettings settings);

    bool IsValidVolumeName(string volume);
}

internal sealed class DockerProxyArgumentParser : IDockerProxyArgumentParser
{
    public DockerProxyWrapperFlags ParseWrapperFlags(IReadOnlyList<string> args)
        => DockerProxyWrapperFlagParsing.ParseWrapperFlags(args);

    public DevcontainerLabels ExtractDevcontainerLabels(IReadOnlyList<string> args)
        => DockerProxyDevcontainerLabelParsing.ExtractDevcontainerLabels(args);

    public bool IsContainerCreateCommand(IReadOnlyList<string> args)
        => DockerProxyCommandParsing.IsContainerCreateCommand(args);

    public string SanitizeWorkspaceName(string value) => DockerProxyValidationHelpers.SanitizeWorkspaceName(value);

    public string? GetFirstSubcommand(IReadOnlyList<string> args)
        => DockerProxyCommandParsing.GetFirstSubcommand(args);

    public string? GetContainerNameArg(IReadOnlyList<string> args, string subcommand)
        => DockerProxyCommandParsing.GetContainerNameArg(args, subcommand);

    public List<string> PrependContext(string contextName, IReadOnlyList<string> args)
        => DockerProxyCommandParsing.PrependContext(contextName, args);
}

internal sealed class DevcontainerFeatureSettingsParser : IDevcontainerFeatureSettingsParser
{
    private readonly ContainAiDockerProxyOptions options;

    public DevcontainerFeatureSettingsParser(ContainAiDockerProxyOptions options) => this.options = options;

    public string StripJsoncComments(string content) => DockerProxyFeatureSettingsParsing.StripJsoncComments(content);

    public bool TryReadFeatureSettings(string configFile, TextWriter stderr, out FeatureSettings settings)
        => DockerProxyFeatureSettingsParsing.TryReadFeatureSettings(configFile, stderr, options, out settings);

    public bool IsValidVolumeName(string volume) => DockerProxyValidationHelpers.IsValidVolumeName(volume);
}

internal readonly record struct DockerProxyWrapperFlags(IReadOnlyList<string> DockerArgs, bool Verbose, bool Quiet);

internal readonly record struct DevcontainerLabels(string? ConfigFile, string? LocalFolder);

internal readonly record struct DockerProxyProcessResult(int ExitCode, string StandardOutput, string StandardError);

internal sealed record ContainAiDockerProxyOptions(string DefaultContext, string DefaultDataVolume, int SshPortRangeStart, int SshPortRangeEnd)
{
    public static ContainAiDockerProxyOptions Default { get; } = new("containai-docker", "containai-data", 2400, 2499);
}

internal readonly record struct FeatureSettings(bool HasContainAiFeature, string DataVolume, bool EnableCredentials, string RemoteUser)
{
    public static FeatureSettings Default(string defaultDataVolume) => new(false, defaultDataVolume, false, "vscode");
}
