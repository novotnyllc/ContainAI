namespace ContainAI.Cli.Host.Devcontainer;

internal interface IDevcontainerSysboxVerificationService
{
    Task<int> VerifySysboxAsync(CancellationToken cancellationToken);
}
