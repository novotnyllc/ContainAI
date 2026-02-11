namespace ContainAI.Cli.Host;

internal sealed partial class ShellProfileHookBlockManager
{
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
