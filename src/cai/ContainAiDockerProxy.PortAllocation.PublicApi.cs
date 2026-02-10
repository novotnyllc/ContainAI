namespace ContainAI.Cli.Host;

internal sealed partial class DockerProxyPortAllocator
{
    public Task<string> AllocateSshPortAsync(
        string lockPath,
        string containAiConfigDir,
        string contextName,
        string workspaceName,
        string workspaceSafe,
        CancellationToken cancellationToken)
        => DockerProxyPortLock.WithPortLockAsync(
            lockPath,
            () => AllocateUnlockedSshPortAsync(containAiConfigDir, contextName, workspaceName, workspaceSafe, cancellationToken),
            cancellationToken);
}
