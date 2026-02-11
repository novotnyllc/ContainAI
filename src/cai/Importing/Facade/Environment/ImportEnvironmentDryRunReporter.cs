namespace ContainAI.Cli.Host;

internal sealed class ImportEnvironmentDryRunReporter
{
    private readonly TextWriter stdout;

    public ImportEnvironmentDryRunReporter(TextWriter standardOutput)
        => stdout = standardOutput ?? throw new ArgumentNullException(nameof(standardOutput));

    public async Task ReportMergedKeysAsync(IReadOnlyDictionary<string, string> merged, CancellationToken cancellationToken)
    {
        _ = cancellationToken;
        foreach (var key in merged.Keys.OrderBy(static value => value, StringComparer.Ordinal))
        {
            await stdout.WriteLineAsync($"[DRY-RUN] env key: {key}").ConfigureAwait(false);
        }
    }
}
