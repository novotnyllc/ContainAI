namespace ContainAI.Cli.Host.Importing.Environment.Source;

internal interface IImportEnvironmentHostValueResolver
{
    Task<Dictionary<string, string>> ResolveAsync(
        IReadOnlyList<string> validatedKeys,
        CancellationToken cancellationToken);
}

internal sealed class ImportEnvironmentHostValueResolver : IImportEnvironmentHostValueResolver
{
    private readonly TextWriter stderr;

    public ImportEnvironmentHostValueResolver(TextWriter standardError)
        => stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));

    public async Task<Dictionary<string, string>> ResolveAsync(
        IReadOnlyList<string> validatedKeys,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        var hostVariables = new Dictionary<string, string>(StringComparer.Ordinal);
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

            hostVariables[key] = envValue;
        }

        return hostVariables;
    }
}
