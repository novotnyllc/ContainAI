namespace ContainAI.Cli.Host;

internal interface ICaiGcConfirmationPrompt
{
    Task<bool> ConfirmAsync(bool dryRun, bool force, int candidateCount);
}
