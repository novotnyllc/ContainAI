namespace ContainAI.Cli.Host;

internal interface IContainerLinkCommandClient
{
    Task<CommandExecutionResult> ExecuteInContainerAsync(
        string containerName,
        IReadOnlyList<string> command,
        CancellationToken cancellationToken);

    Task<CommandExecutionResult> ExecuteInContainerWithInputAsync(
        string containerName,
        IReadOnlyList<string> command,
        string standardInput,
        CancellationToken cancellationToken);

    Task<bool> TestInContainerAsync(
        string containerName,
        string testOption,
        string path,
        CancellationToken cancellationToken);
}
