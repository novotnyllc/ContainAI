namespace ContainAI.Cli.Host;

internal sealed partial class ShellProfileHookBlockManager
{
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
}
