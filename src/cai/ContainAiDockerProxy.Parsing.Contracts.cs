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
