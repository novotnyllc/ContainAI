namespace ContainAI.Cli.Host;

internal sealed partial class ExamplesCommandRuntime
{
    public async Task<int> RunListAsync(CancellationToken cancellationToken)
    {
        var examples = dictionaryProvider.GetExamples();
        if (examples.Count == 0)
        {
            await stderr.WriteLineAsync("[ERROR] No embedded examples are available.").ConfigureAwait(false);
            return 1;
        }

        cancellationToken.ThrowIfCancellationRequested();
        await stdout.WriteLineAsync("Available example TOML files:").ConfigureAwait(false);
        foreach (var fileName in examples.Keys.OrderBy(static name => name, StringComparer.Ordinal))
        {
            cancellationToken.ThrowIfCancellationRequested();
            await stdout.WriteLineAsync($"  {fileName}").ConfigureAwait(false);
        }

        return 0;
    }
}
