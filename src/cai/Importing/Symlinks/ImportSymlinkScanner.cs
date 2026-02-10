using System.Diagnostics;

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
            IEnumerable<string> entries;
            try
            {
                entries = Directory.EnumerateFileSystemEntries(currentDirectory);
            }
            catch (IOException)
            {
                continue;
            }
            catch (UnauthorizedAccessException)
            {
                continue;
            }
            catch (NotSupportedException)
            {
                continue;
            }
            catch (ArgumentException)
            {
                continue;
            }

            foreach (var entry in entries)
            {
                if (IsSymbolicLinkPath(entry))
                {
                    var linkTarget = ReadSymlinkTarget(entry);
                    if (!string.IsNullOrWhiteSpace(linkTarget))
                    {
                        var relativePath = Path.GetRelativePath(sourceDirectoryPath, entry).Replace('\\', '/');
                        symlinks.Add(new ImportSymlink(relativePath, linkTarget));
                    }

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

    private static string? ReadSymlinkTarget(string path)
    {
        try
        {
            var fileInfo = new FileInfo(path);
            if (!string.IsNullOrWhiteSpace(fileInfo.LinkTarget))
            {
                return fileInfo.LinkTarget;
            }
        }
        catch (IOException ex)
        {
            Debug.WriteLine($"Failed to read file symlink target for '{path}': {ex.Message}");
        }
        catch (NotSupportedException ex)
        {
            Debug.WriteLine($"Failed to read file symlink target for '{path}': {ex.Message}");
        }
        catch (ArgumentException ex)
        {
            Debug.WriteLine($"Failed to read file symlink target for '{path}': {ex.Message}");
        }

        try
        {
            var directoryInfo = new DirectoryInfo(path);
            if (!string.IsNullOrWhiteSpace(directoryInfo.LinkTarget))
            {
                return directoryInfo.LinkTarget;
            }
        }
        catch (IOException ex)
        {
            Debug.WriteLine($"Failed to read directory symlink target for '{path}': {ex.Message}");
        }
        catch (NotSupportedException ex)
        {
            Debug.WriteLine($"Failed to read directory symlink target for '{path}': {ex.Message}");
        }
        catch (ArgumentException ex)
        {
            Debug.WriteLine($"Failed to read directory symlink target for '{path}': {ex.Message}");
        }

        return null;
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
}
