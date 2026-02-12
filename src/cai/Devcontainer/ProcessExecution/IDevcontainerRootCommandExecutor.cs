namespace ContainAI.Cli.Host.Devcontainer.ProcessExecution;

internal interface IDevcontainerRootCommandExecutor
{
    Task RunAsRootAsync(string executable, IReadOnlyList<string> arguments, CancellationToken cancellationToken);
}
