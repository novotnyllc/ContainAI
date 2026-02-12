namespace ContainAI.Cli.Host.DockerProxy.Ports;

internal static class DockerProxyPortLock
{
    public static async Task<T> WithPortLockAsync<T>(string lockPath, Func<Task<T>> action, CancellationToken cancellationToken)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(lockPath)!);

        for (var attempt = 0; attempt < 100; attempt++)
        {
            cancellationToken.ThrowIfCancellationRequested();
            try
            {
                await using var stream = new FileStream(lockPath, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None).ConfigureAwait(false);
                return await action().ConfigureAwait(false);
            }
            catch (IOException)
            {
                await Task.Delay(100, cancellationToken).ConfigureAwait(false);
            }
        }

        return await action().ConfigureAwait(false);
    }
}
