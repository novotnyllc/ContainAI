namespace ContainAI.Cli.Host;

internal interface IExamplesListCommandRunner
{
    Task<int> RunAsync(IReadOnlyDictionary<string, string> examples, CancellationToken cancellationToken);
}
