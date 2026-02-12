namespace ContainAI.Cli.Host.DockerProxy.System;

internal interface IDockerProxyVolumeCredentialValidator
{
    Task<bool> ValidateAsync(
        string contextName,
        string dataVolume,
        bool enableCredentials,
        bool quiet,
        TextWriter stderr,
        CancellationToken cancellationToken);
}
