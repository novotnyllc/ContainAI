namespace ContainAI.Cli.Host.Importing.Symlinks;

internal sealed partial class ImportSymlinkScanner : IImportSymlinkScanner
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
}
