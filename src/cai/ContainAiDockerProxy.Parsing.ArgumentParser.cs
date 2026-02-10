namespace ContainAI.Cli.Host;

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
