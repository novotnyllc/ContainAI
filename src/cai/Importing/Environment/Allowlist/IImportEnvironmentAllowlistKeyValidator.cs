using ContainAI.Cli.Host.RuntimeSupport.Environment;

namespace ContainAI.Cli.Host.Importing.Environment;

internal interface IImportEnvironmentAllowlistKeyValidator
{
    Task<List<string>> ValidateAsync(List<string> importKeys);
}
