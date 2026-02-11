using System.Text.Json;
using ContainAI.Cli.Host.RuntimeSupport.Environment;

namespace ContainAI.Cli.Host.Importing.Environment;

internal interface IImportEnvironmentSourceOperations
{
    Task<Dictionary<string, string>?> ResolveFileVariablesAsync(
        JsonElement envSection,
        string workspaceRoot,
        IReadOnlyCollection<string> validatedKeys,
        CancellationToken cancellationToken);

    Task<bool> ResolveFromHostFlagAsync(JsonElement envSection, CancellationToken cancellationToken);

    Task<Dictionary<string, string>> MergeVariablesWithHostValuesAsync(
        Dictionary<string, string> fileVariables,
        IReadOnlyList<string> validatedKeys,
        bool fromHost,
        CancellationToken cancellationToken);
}

internal sealed class ImportEnvironmentSourceOperations : IImportEnvironmentSourceOperations
{
    private readonly TextWriter stderr;

    public ImportEnvironmentSourceOperations(TextWriter standardOutput, TextWriter standardError)
    {
        ArgumentNullException.ThrowIfNull(standardOutput);
        stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));
    }

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
                var envFileResolution = CaiRuntimeEnvFileHelpers.ResolveEnvFilePath(workspaceRoot, envFile);
                if (envFileResolution.Error is not null)
                {
                    await stderr.WriteLineAsync(envFileResolution.Error).ConfigureAwait(false);
                    return null;
                }

                if (envFileResolution.Path is not null)
                {
                    var parsed = CaiRuntimeEnvFileHelpers.ParseEnvFile(envFileResolution.Path);
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

    public async Task<bool> ResolveFromHostFlagAsync(JsonElement envSection, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        if (envSection.TryGetProperty("from_host", out var fromHostElement))
        {
            if (fromHostElement.ValueKind == JsonValueKind.True)
            {
                return true;
            }

            if (fromHostElement.ValueKind != JsonValueKind.False)
            {
                await stderr.WriteLineAsync("[WARN] [env].from_host must be a boolean; using false").ConfigureAwait(false);
            }
        }

        return false;
    }

    public async Task<Dictionary<string, string>> MergeVariablesWithHostValuesAsync(
        Dictionary<string, string> fileVariables,
        IReadOnlyList<string> validatedKeys,
        bool fromHost,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        var merged = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var (key, value) in fileVariables)
        {
            merged[key] = value;
        }

        if (!fromHost)
        {
            return merged;
        }

        foreach (var key in validatedKeys)
        {
            var envValue = System.Environment.GetEnvironmentVariable(key);
            if (envValue is null)
            {
                await stderr.WriteLineAsync($"[WARN] Missing host env var: {key}").ConfigureAwait(false);
                continue;
            }

            if (envValue.Contains('\n', StringComparison.Ordinal))
            {
                await stderr.WriteLineAsync($"[WARN] source=host: key '{key}' skipped (multiline value)").ConfigureAwait(false);
                continue;
            }

            merged[key] = envValue;
        }

        return merged;
    }
}
