namespace ContainAI.Cli.Host.Devcontainer;

internal interface IDevcontainerUserEnvironmentSetup
{
    Task<string> DetectUserHomeAsync(string remoteUser, CancellationToken cancellationToken);

    Task AddUserToDockerGroupIfPresentAsync(string user, CancellationToken cancellationToken);
}
