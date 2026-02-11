namespace ContainAI.Cli.Host.Importing.Symlinks;

internal sealed class ImportSymlinkScanner : IImportSymlinkScanner
{
    public IReadOnlyList<ImportSymlink> CollectSymlinksForRelink(string sourceDirectoryPath)
    {
        var symlinks = new List<ImportSymlink>();
        var stack = new Stack<string>();
        stack.Push(sourceDirectoryPath);
        while (stack.Count > 0)
        {
            var currentDirectory = stack.Pop();
            if (!TryEnumerateEntries(currentDirectory, out var entries))
            {
                continue;
            }

            foreach (var entry in entries)
            {
                if (IsSymbolicLinkPath(entry))
                {
                    TryAddSymlink(sourceDirectoryPath, entry, symlinks);
                    continue;
                }

                if (Directory.Exists(entry))
                {
                    stack.Push(entry);
                }
            }
        }

        return symlinks;
    }

    private static bool TryEnumerateEntries(string directory, out IEnumerable<string> entries)
    {
        entries = Array.Empty<string>();
        try
        {
            entries = Directory.EnumerateFileSystemEntries(directory);
            return true;
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

    private static bool IsSymbolicLinkPath(string path)
    {
        try
        {
            var attributes = File.GetAttributes(path);
            return (attributes & FileAttributes.ReparsePoint) != 0;
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

    private static void TryAddSymlink(string sourceDirectoryPath, string entry, List<ImportSymlink> symlinks)
    {
        var linkTarget = ReadSymlinkTarget(entry);
        if (!string.IsNullOrWhiteSpace(linkTarget))
        {
            var relativePath = Path.GetRelativePath(sourceDirectoryPath, entry).Replace('\\', '/');
            symlinks.Add(new ImportSymlink(relativePath, linkTarget));
        }
    }

    private static string? ReadSymlinkTarget(string path)
        => TryReadFileLinkTarget(path) ?? TryReadDirectoryLinkTarget(path);

    private static string? TryReadFileLinkTarget(string path)
    {
        try
        {
            var fileInfo = new FileInfo(path);
            if (!string.IsNullOrWhiteSpace(fileInfo.LinkTarget))
            {
                return fileInfo.LinkTarget;
            }
        }
        catch (IOException)
        {
            return null;
        }
        catch (NotSupportedException)
        {
            return null;
        }
        catch (ArgumentException)
        {
            return null;
        }

        return null;
    }

    private static string? TryReadDirectoryLinkTarget(string path)
    {
        try
        {
            var directoryInfo = new DirectoryInfo(path);
            if (!string.IsNullOrWhiteSpace(directoryInfo.LinkTarget))
            {
                return directoryInfo.LinkTarget;
            }
        }
        catch (IOException)
        {
            return null;
        }
        catch (NotSupportedException)
        {
            return null;
        }
        catch (ArgumentException)
        {
            return null;
        }

        return null;
    }
}
