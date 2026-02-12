namespace ContainAI.Cli.Host.Devcontainer;

internal interface IDevcontainerServiceBootstrap
{
    Task<int> VerifySysboxAsync(CancellationToken cancellationToken);

    Task<int> StartSshdAsync(CancellationToken cancellationToken);

    Task<int> StartDockerdAsync(CancellationToken cancellationToken);
}
