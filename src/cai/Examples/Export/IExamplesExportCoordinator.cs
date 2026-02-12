using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal interface IExamplesExportCoordinator
{
    Task<int> RunAsync(
        IReadOnlyDictionary<string, string> examples,
        ExamplesExportCommandOptions options,
        CancellationToken cancellationToken);
}
