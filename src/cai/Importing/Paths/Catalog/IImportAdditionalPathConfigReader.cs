using ContainAI.Cli.Host.RuntimeSupport.Parsing;

namespace ContainAI.Cli.Host.Importing.Paths;

internal interface IImportAdditionalPathConfigReader
{
    Task<IReadOnlyList<string>> ReadRawAdditionalPathsAsync(
        string configPath,
        bool verbose,
        CancellationToken cancellationToken);
}
