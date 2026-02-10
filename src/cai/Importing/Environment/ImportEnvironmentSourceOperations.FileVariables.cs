using System.Text.Json;

namespace ContainAI.Cli.Host.Importing.Environment;

internal sealed partial class ImportEnvironmentSourceOperations
{
    public async Task<Dictionary<string, string>?> ResolveFileVariablesAsync(
        JsonElement envSection,
        string workspaceRoot,
        IReadOnlyCollection<string> validatedKeys,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        var fileVariables = new Dictionary<string, string>(StringComparer.Ordinal);
        if (envSection.TryGetProperty("env_file", out var envFileElement) && envFileElement.ValueKind == JsonValueKind.String)
        {
            var envFile = envFileElement.GetString();
            if (!string.IsNullOrWhiteSpace(envFile))
            {
                var envFileResolution = ResolveEnvFilePath(workspaceRoot, envFile);
                if (envFileResolution.Error is not null)
                {
                    await stderr.WriteLineAsync(envFileResolution.Error).ConfigureAwait(false);
                    return null;
                }

                if (envFileResolution.Path is not null)
                {
                    var parsed = ParseEnvFile(envFileResolution.Path);
                    foreach (var warning in parsed.Warnings)
                    {
                        await stderr.WriteLineAsync(warning).ConfigureAwait(false);
                    }

                    foreach (var (key, value) in parsed.Values)
                    {
                        if (validatedKeys.Contains(key))
                        {
                            fileVariables[key] = value;
                        }
                    }
                }
            }
        }

        return fileVariables;
    }
}
