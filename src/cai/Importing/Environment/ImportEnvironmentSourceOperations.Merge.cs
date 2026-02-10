namespace ContainAI.Cli.Host.Importing.Environment;

internal sealed partial class ImportEnvironmentSourceOperations
{
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
