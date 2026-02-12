namespace ContainAI.Cli.Host;

internal sealed class CaiUpdateUsageWriter : ICaiUpdateUsageWriter
{
    private readonly TextWriter stdout;

    public CaiUpdateUsageWriter(TextWriter standardOutput)
        => stdout = standardOutput ?? throw new ArgumentNullException(nameof(standardOutput));

    public async Task<int> WriteUpdateUsageAsync()
    {
        await stdout.WriteLineAsync("Usage: cai update [--dry-run] [--stop-containers] [--force] [--lima-recreate]").ConfigureAwait(false);
        return 0;
    }
}
