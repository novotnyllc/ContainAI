using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal abstract partial class CaiRuntimeSupport
{
    protected static bool IsSymbolicLinkPath(string path)
    {
        try
        {
            return (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0;
        }
        catch (IOException)
        {
            return false;
        }
        catch (UnauthorizedAccessException)
        {
            return false;
        }
        catch (NotSupportedException)
        {
            return false;
        }
        catch (ArgumentException)
        {
            return false;
        }
    }

    protected static bool TryMapSourcePathToTarget(
        string sourceRelativePath,
        IReadOnlyList<ManifestEntry> entries,
        out string targetRelativePath,
        out string flags)
    {
        targetRelativePath = string.Empty;
        flags = string.Empty;

        var normalizedSource = sourceRelativePath.Replace("\\", "/", StringComparison.Ordinal);
        ManifestEntry? match = null;
        var bestLength = -1;
        string? suffix = null;

        foreach (var entry in entries)
        {
            if (string.IsNullOrWhiteSpace(entry.Source))
            {
                continue;
            }

            var entrySource = entry.Source.Replace("\\", "/", StringComparison.Ordinal).TrimEnd('/');
            var isDirectory = entry.Flags.Contains('d', StringComparison.Ordinal);
            if (isDirectory)
            {
                var prefix = $"{entrySource}/";
                if (!normalizedSource.StartsWith(prefix, StringComparison.Ordinal) &&
                    !string.Equals(normalizedSource, entrySource, StringComparison.Ordinal))
                {
                    continue;
                }

                if (entrySource.Length <= bestLength)
                {
                    continue;
                }

                match = entry;
                bestLength = entrySource.Length;
                suffix = string.Equals(normalizedSource, entrySource, StringComparison.Ordinal)
                    ? string.Empty
                    : normalizedSource[prefix.Length..];
                continue;
            }

            if (!string.Equals(normalizedSource, entrySource, StringComparison.Ordinal))
            {
                continue;
            }

            if (entrySource.Length <= bestLength)
            {
                continue;
            }

            match = entry;
            bestLength = entrySource.Length;
            suffix = null;
        }

        if (match is null)
        {
            return false;
        }

        flags = match.Value.Flags;
        targetRelativePath = string.IsNullOrEmpty(suffix)
            ? match.Value.Target
            : $"{match.Value.Target.TrimEnd('/')}/{suffix}";
        return true;
    }

    protected static string EscapeForSingleQuotedShell(string value)
        => value.Replace("'", "'\"'\"'", StringComparison.Ordinal);
}
