using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal interface IImportOrchestrationOperations
{
    Task<int> RunImportAsync(ImportCommandOptions options, CancellationToken cancellationToken);
}
