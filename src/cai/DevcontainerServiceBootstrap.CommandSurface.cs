namespace ContainAI.Cli.Host;

internal sealed partial class DevcontainerServiceBootstrap
{
    public Task<int> VerifySysboxAsync(CancellationToken cancellationToken)
        => sysboxVerificationService.VerifySysboxAsync(cancellationToken);

    public Task<int> StartSshdAsync(CancellationToken cancellationToken)
        => sshdStartupService.StartSshdAsync(cancellationToken);

    public Task<int> StartDockerdAsync(CancellationToken cancellationToken)
        => dockerdStartupService.StartDockerdAsync(cancellationToken);
}
