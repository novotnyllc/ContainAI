namespace ContainAI.Cli.Host;

internal interface IDockerProxyContextSelector
{
    Task<bool> ShouldUseContainAiContextAsync(IReadOnlyList<string> args, string contextName, CancellationToken cancellationToken);
}

internal sealed class DockerProxyContextSelector : IDockerProxyContextSelector
{
    private static readonly HashSet<string> ContainerTargetingSubcommands =
    [
        "exec",
        "inspect",
        "start",
        "stop",
        "rm",
        "logs",
        "restart",
        "kill",
        "pause",
        "unpause",
        "port",
        "stats",
        "top",
    ];

    private readonly IDockerProxyArgumentParser argumentParser;
    private readonly IDockerProxyCommandExecutor commandExecutor;

    public DockerProxyContextSelector(IDockerProxyArgumentParser argumentParser, IDockerProxyCommandExecutor commandExecutor)
    {
        this.argumentParser = argumentParser;
        this.commandExecutor = commandExecutor;
    }

    public async Task<bool> ShouldUseContainAiContextAsync(IReadOnlyList<string> args, string contextName, CancellationToken cancellationToken)
    {
        foreach (var arg in args)
        {
            if (string.Equals(arg, "--context", StringComparison.Ordinal) || arg.StartsWith("--context=", StringComparison.Ordinal))
            {
                return false;
            }

            if (arg.Contains("devcontainer.", StringComparison.Ordinal) || arg.Contains("containai.", StringComparison.Ordinal))
            {
                return true;
            }
        }

        var subcommand = argumentParser.GetFirstSubcommand(args);
        if (string.IsNullOrWhiteSpace(subcommand) || !ContainerTargetingSubcommands.Contains(subcommand))
        {
            return false;
        }

        var containerName = argumentParser.GetContainerNameArg(args, subcommand);
        if (string.IsNullOrWhiteSpace(containerName))
        {
            return false;
        }

        var probe = await commandExecutor.RunCaptureAsync(
            ["--context", contextName, "inspect", containerName],
            cancellationToken).ConfigureAwait(false);
        return probe.ExitCode == 0;
    }
}
