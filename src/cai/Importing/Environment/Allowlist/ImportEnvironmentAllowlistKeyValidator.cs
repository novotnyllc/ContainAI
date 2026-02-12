using ContainAI.Cli.Host.RuntimeSupport.Environment;

namespace ContainAI.Cli.Host.Importing.Environment;

internal sealed class ImportEnvironmentAllowlistKeyValidator(TextWriter standardError) : IImportEnvironmentAllowlistKeyValidator
{
    public async Task<List<string>> ValidateAsync(List<string> importKeys)
    {
        ArgumentNullException.ThrowIfNull(importKeys);

        var validatedKeys = new List<string>(importKeys.Count);
        foreach (var key in importKeys)
        {
            if (!CaiRuntimeEnvRegexHelpers.EnvVarNameRegex().IsMatch(key))
            {
                await standardError.WriteLineAsync($"[WARN] Invalid env var name in allowlist: {key}").ConfigureAwait(false);
                continue;
            }

            validatedKeys.Add(key);
        }

        return validatedKeys;
    }
}
