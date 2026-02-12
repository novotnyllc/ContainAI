namespace ContainAI.Cli.Host;

internal sealed class ShellProfileHookFileOperations : IShellProfileHookFileOperations
{
    private readonly IShellProfileFileSystem fileSystem;
    private readonly IShellProfileHookBlockManager hookBlockManager;

    public ShellProfileHookFileOperations(
        IShellProfileFileSystem fileSystem,
        IShellProfileHookBlockManager hookBlockManager)
    {
        this.fileSystem = fileSystem ?? throw new ArgumentNullException(nameof(fileSystem));
        this.hookBlockManager = hookBlockManager ?? throw new ArgumentNullException(nameof(hookBlockManager));
    }

    public async Task<bool> EnsureHookInShellProfileAsync(string shellProfilePath, CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(shellProfilePath);

        var shellProfileDirectory = Path.GetDirectoryName(shellProfilePath);
        if (!string.IsNullOrWhiteSpace(shellProfileDirectory))
        {
            fileSystem.CreateDirectory(shellProfileDirectory);
        }

        var existing = fileSystem.FileExists(shellProfilePath)
            ? await fileSystem.ReadAllTextAsync(shellProfilePath, cancellationToken).ConfigureAwait(false)
            : string.Empty;
        if (hookBlockManager.HasHookBlock(existing))
        {
            return false;
        }

        var hookBlock = hookBlockManager.BuildHookBlock();
        var updated = string.IsNullOrWhiteSpace(existing)
            ? hookBlock + Environment.NewLine
            : existing.TrimEnd() + Environment.NewLine + Environment.NewLine + hookBlock + Environment.NewLine;
        await fileSystem.WriteAllTextAsync(shellProfilePath, updated, cancellationToken).ConfigureAwait(false);
        return true;
    }

    public async Task<bool> RemoveHookFromShellProfileAsync(string shellProfilePath, CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(shellProfilePath);

        if (!fileSystem.FileExists(shellProfilePath))
        {
            return false;
        }

        var existing = await fileSystem.ReadAllTextAsync(shellProfilePath, cancellationToken).ConfigureAwait(false);
        if (!hookBlockManager.TryRemoveHookBlock(existing, out var updated))
        {
            return false;
        }

        await fileSystem.WriteAllTextAsync(shellProfilePath, updated, cancellationToken).ConfigureAwait(false);
        return true;
    }
}
