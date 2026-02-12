using System.Text.Json;

namespace ContainAI.Cli.Host.Importing.Environment;

internal interface IImportEnvironmentAllowlistParser
{
    Task<List<string>> ParseImportKeysAsync(JsonElement envSection);
}
