using System.Text.Json;

namespace ContainAI.Cli.Host.Importing.Paths;

internal interface IImportAdditionalPathJsonReader
{
    Task<IReadOnlyList<string>> ReadRawAdditionalPathsAsync(
        string configJson,
        bool verbose);
}
