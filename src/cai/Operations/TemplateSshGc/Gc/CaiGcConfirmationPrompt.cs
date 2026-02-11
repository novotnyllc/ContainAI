namespace ContainAI.Cli.Host;

internal interface ICaiGcConfirmationPrompt
{
    Task<bool> ConfirmAsync(bool dryRun, bool force, int candidateCount);
}

internal sealed class CaiGcConfirmationPrompt : ICaiGcConfirmationPrompt
{
    private readonly TextWriter stdout;
    private readonly TextWriter stderr;

    public CaiGcConfirmationPrompt(TextWriter standardOutput, TextWriter standardError)
    {
        stdout = standardOutput ?? throw new ArgumentNullException(nameof(standardOutput));
        stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));
    }

    public async Task<bool> ConfirmAsync(bool dryRun, bool force, int candidateCount)
    {
        if (dryRun || force || candidateCount == 0)
        {
            return true;
        }

        if (Console.IsInputRedirected)
        {
            await stderr.WriteLineAsync("gc requires --force in non-interactive mode.").ConfigureAwait(false);
            return false;
        }

        await stdout.WriteLineAsync($"About to remove {candidateCount} containers. Continue? [y/N]").ConfigureAwait(false);
        var response = (Console.ReadLine() ?? string.Empty).Trim();
        if (!response.Equals("y", StringComparison.OrdinalIgnoreCase) &&
            !response.Equals("yes", StringComparison.OrdinalIgnoreCase))
        {
            await stdout.WriteLineAsync("Aborted.").ConfigureAwait(false);
            return false;
        }

        return true;
    }
}
