namespace ContainAI.Cli.Host.Devcontainer.ProcessExecution;

internal interface IDevcontainerProcessCommandProbe
{
    Task<bool> CommandExistsAsync(string command, CancellationToken cancellationToken);

    Task<bool> CommandSucceedsAsync(string executable, IReadOnlyList<string> arguments, CancellationToken cancellationToken);
}
