namespace ContainAI.Cli.Host;

internal sealed class ExamplesListCommandRunner(TextWriter standardOutput, TextWriter standardError) : IExamplesListCommandRunner
{
    public async Task<int> RunAsync(IReadOnlyDictionary<string, string> examples, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(examples);

        if (examples.Count == 0)
        {
            await standardError.WriteLineAsync("[ERROR] No embedded examples are available.").ConfigureAwait(false);
            return 1;
        }

        cancellationToken.ThrowIfCancellationRequested();
        await standardOutput.WriteLineAsync("Available example TOML files:").ConfigureAwait(false);
        foreach (var fileName in examples.Keys.OrderBy(static name => name, StringComparer.Ordinal))
        {
            cancellationToken.ThrowIfCancellationRequested();
            await standardOutput.WriteLineAsync($"  {fileName}").ConfigureAwait(false);
        }

        return 0;
    }
}
