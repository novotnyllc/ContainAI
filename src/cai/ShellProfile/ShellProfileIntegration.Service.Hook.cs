namespace ContainAI.Cli.Host;

internal sealed partial class ShellProfileIntegrationService
{
    public async Task<bool> EnsureHookInShellProfileAsync(string shellProfilePath, CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(shellProfilePath);

        var shellProfileDirectory = Path.GetDirectoryName(shellProfilePath);
        if (!string.IsNullOrWhiteSpace(shellProfileDirectory))
        {
            Directory.CreateDirectory(shellProfileDirectory);
        }

        var existing = File.Exists(shellProfilePath)
            ? await File.ReadAllTextAsync(shellProfilePath, cancellationToken).ConfigureAwait(false)
            : string.Empty;
        if (HasHookBlock(existing))
        {
            return false;
        }

        var hookBlock = hookBlockManager.BuildHookBlock();
        var updated = string.IsNullOrWhiteSpace(existing)
            ? hookBlock + Environment.NewLine
            : existing.TrimEnd() + Environment.NewLine + Environment.NewLine + hookBlock + Environment.NewLine;
        await File.WriteAllTextAsync(shellProfilePath, updated, cancellationToken).ConfigureAwait(false);
        return true;
    }

    public async Task<bool> RemoveHookFromShellProfileAsync(string shellProfilePath, CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(shellProfilePath);

        if (!File.Exists(shellProfilePath))
        {
            return false;
        }

        var existing = await File.ReadAllTextAsync(shellProfilePath, cancellationToken).ConfigureAwait(false);
        if (!hookBlockManager.TryRemoveHookBlock(existing, out var updated))
        {
            return false;
        }

        await File.WriteAllTextAsync(shellProfilePath, updated, cancellationToken).ConfigureAwait(false);
        return true;
    }
}
