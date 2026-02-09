namespace ContainAI.Cli.Host;

internal static partial class ShellProfileIntegration
{
    public static async Task<bool> EnsureProfileScriptAsync(string homeDirectory, string binDirectory, CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(homeDirectory);
        ArgumentException.ThrowIfNullOrWhiteSpace(binDirectory);

        var profileScriptPath = GetProfileScriptPath(homeDirectory);
        Directory.CreateDirectory(Path.GetDirectoryName(profileScriptPath)!);

        var script = BuildProfileScript(homeDirectory, binDirectory);
        if (File.Exists(profileScriptPath))
        {
            var existing = await File.ReadAllTextAsync(profileScriptPath, cancellationToken).ConfigureAwait(false);
            if (string.Equals(existing, script, StringComparison.Ordinal))
            {
                return false;
            }
        }

        await File.WriteAllTextAsync(profileScriptPath, script, cancellationToken).ConfigureAwait(false);
        return true;
    }

    public static async Task<bool> EnsureHookInShellProfileAsync(string shellProfilePath, CancellationToken cancellationToken)
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

        var hookBlock = BuildHookBlock();
        var updated = string.IsNullOrWhiteSpace(existing)
            ? hookBlock + Environment.NewLine
            : existing.TrimEnd() + Environment.NewLine + Environment.NewLine + hookBlock + Environment.NewLine;
        await File.WriteAllTextAsync(shellProfilePath, updated, cancellationToken).ConfigureAwait(false);
        return true;
    }

    public static async Task<bool> RemoveHookFromShellProfileAsync(string shellProfilePath, CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(shellProfilePath);

        if (!File.Exists(shellProfilePath))
        {
            return false;
        }

        var existing = await File.ReadAllTextAsync(shellProfilePath, cancellationToken).ConfigureAwait(false);
        if (!TryRemoveHookBlock(existing, out var updated))
        {
            return false;
        }

        await File.WriteAllTextAsync(shellProfilePath, updated, cancellationToken).ConfigureAwait(false);
        return true;
    }

    public static Task<bool> RemoveProfileScriptAsync(string homeDirectory, CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(homeDirectory);
        cancellationToken.ThrowIfCancellationRequested();

        var profileScriptPath = GetProfileScriptPath(homeDirectory);
        if (!File.Exists(profileScriptPath))
        {
            return Task.FromResult(false);
        }

        File.Delete(profileScriptPath);

        var profileDirectory = GetProfileDirectoryPath(homeDirectory);
        if (Directory.Exists(profileDirectory) && !Directory.EnumerateFileSystemEntries(profileDirectory).Any())
        {
            Directory.Delete(profileDirectory);
        }

        return Task.FromResult(true);
    }

    private static bool TryRemoveHookBlock(string content, out string updated)
    {
        updated = content;
        var removed = false;
        while (TryFindHookRange(updated, out var startIndex, out var endIndex))
        {
            updated = updated.Remove(startIndex, endIndex - startIndex);
            removed = true;
        }

        if (!removed)
        {
            return false;
        }

        updated = updated.TrimEnd('\r', '\n');
        if (updated.Length > 0)
        {
            updated += Environment.NewLine;
        }

        return true;
    }

    private static bool TryFindHookRange(string content, out int startIndex, out int endIndex)
    {
        startIndex = content.IndexOf(ShellIntegrationStartMarker, StringComparison.Ordinal);
        if (startIndex < 0)
        {
            endIndex = -1;
            return false;
        }

        var lineStart = content.LastIndexOf('\n', Math.Max(startIndex - 1, 0));
        startIndex = lineStart < 0 ? 0 : lineStart + 1;

        var endMarkerIndex = content.IndexOf(ShellIntegrationEndMarker, startIndex, StringComparison.Ordinal);
        if (endMarkerIndex < 0)
        {
            endIndex = -1;
            return false;
        }

        var lineEnd = content.IndexOf('\n', endMarkerIndex);
        endIndex = lineEnd < 0 ? content.Length : lineEnd + 1;
        return true;
    }
}
