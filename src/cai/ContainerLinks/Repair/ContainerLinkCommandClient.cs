namespace ContainAI.Cli.Host;

internal sealed class ContainerLinkCommandClient(DockerCommandExecutor dockerExecutor) : IContainerLinkCommandClient
{
    public Task<CommandExecutionResult> ExecuteInContainerAsync(
        string containerName,
        IReadOnlyList<string> command,
        CancellationToken cancellationToken)
    {
        var args = BuildExecArguments(containerName, command);
        return dockerExecutor(args, null, cancellationToken);
    }

    public Task<CommandExecutionResult> ExecuteInContainerWithInputAsync(
        string containerName,
        IReadOnlyList<string> command,
        string standardInput,
        CancellationToken cancellationToken)
    {
        var args = BuildExecArguments(containerName, command, interactive: true);
        return dockerExecutor(args, standardInput, cancellationToken);
    }

    public async Task<bool> TestInContainerAsync(
        string containerName,
        string testOption,
        string path,
        CancellationToken cancellationToken)
    {
        var result = await ExecuteInContainerAsync(containerName, ["test", testOption, "--", path], cancellationToken).ConfigureAwait(false);
        return result.ExitCode == 0;
    }

    private static List<string> BuildExecArguments(
        string containerName,
        IReadOnlyList<string> command,
        bool interactive = false)
    {
        var capacity = command.Count + (interactive ? 3 : 2);
        var args = new List<string>(capacity) { "exec" };
        if (interactive)
        {
            args.Add("-i");
        }

        args.Add(containerName);
        args.AddRange(command);
        return args;
    }
}
