namespace ContainAI.Cli.Host.DockerProxy.Models;

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
