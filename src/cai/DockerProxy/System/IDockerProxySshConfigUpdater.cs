namespace ContainAI.Cli.Host.DockerProxy.System;

internal interface IDockerProxySshConfigUpdater
{
    Task UpdateAsync(string workspaceName, string sshPort, string remoteUser, TextWriter stderr, CancellationToken cancellationToken);
}
