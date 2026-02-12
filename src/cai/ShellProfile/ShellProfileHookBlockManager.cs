namespace ContainAI.Cli.Host;

internal sealed class ShellProfileHookBlockManager : IShellProfileHookBlockManager
{
    public bool HasHookBlock(string content)
        => content.Contains(ShellProfileIntegrationConstants.ShellIntegrationStartMarker, StringComparison.Ordinal)
           && content.Contains(ShellProfileIntegrationConstants.ShellIntegrationEndMarker, StringComparison.Ordinal);

    public string BuildHookBlock()
    {
        var profileDirectory = "$HOME/" + ShellProfileIntegrationConstants.ProfileDirectoryRelativePath;
        return string.Join(
            Environment.NewLine,
            ShellProfileIntegrationConstants.ShellIntegrationStartMarker,
            $"if [ -d \"{profileDirectory}\" ]; then",
            $"  for _cai_profile in \"{profileDirectory}/\"*.sh; do",
            "    [ -r \"$_cai_profile\" ] && . \"$_cai_profile\"",
            "  done",
            "  unset _cai_profile",
            "fi",
            ShellProfileIntegrationConstants.ShellIntegrationEndMarker);
    }

    public bool TryRemoveHookBlock(string content, out string updated)
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
        startIndex = content.IndexOf(ShellProfileIntegrationConstants.ShellIntegrationStartMarker, StringComparison.Ordinal);
        if (startIndex < 0)
        {
            endIndex = -1;
            return false;
        }

        var lineStart = content.LastIndexOf('\n', Math.Max(startIndex - 1, 0));
        startIndex = lineStart < 0 ? 0 : lineStart + 1;

        var endMarkerIndex = content.IndexOf(ShellProfileIntegrationConstants.ShellIntegrationEndMarker, startIndex, StringComparison.Ordinal);
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
