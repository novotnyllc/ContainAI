using ContainAI.Cli.Host.RuntimeSupport.Paths;

namespace ContainAI.Cli.Host.Importing.Symlinks;

internal sealed class ImportSymlinkScanner : IImportSymlinkScanner
{
    private readonly IImportDirectoryEntryEnumerator directoryEntryEnumerator;
    private readonly IImportSymlinkTargetReader symlinkTargetReader;

    public ImportSymlinkScanner()
        : this(new ImportDirectoryEntryEnumerator(), new ImportSymlinkTargetReader())
    {
    }

    internal ImportSymlinkScanner(
        IImportDirectoryEntryEnumerator importDirectoryEntryEnumerator,
        IImportSymlinkTargetReader importSymlinkTargetReader)
    {
        directoryEntryEnumerator = importDirectoryEntryEnumerator ?? throw new ArgumentNullException(nameof(importDirectoryEntryEnumerator));
        symlinkTargetReader = importSymlinkTargetReader ?? throw new ArgumentNullException(nameof(importSymlinkTargetReader));
    }

    public IReadOnlyList<ImportSymlink> CollectSymlinksForRelink(string sourceDirectoryPath)
    {
        var symlinks = new List<ImportSymlink>();
        var stack = new Stack<string>();
        stack.Push(sourceDirectoryPath);

        while (stack.Count > 0)
        {
            var currentDirectory = stack.Pop();
            if (!directoryEntryEnumerator.TryEnumerateEntries(currentDirectory, out var entries))
            {
                continue;
            }

            foreach (var entry in entries)
            {
                if (CaiRuntimePathHelpers.IsSymbolicLinkPath(entry))
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

    private void TryAddSymlink(string sourceDirectoryPath, string entry, List<ImportSymlink> symlinks)
    {
        var linkTarget = symlinkTargetReader.ReadSymlinkTarget(entry);
        if (string.IsNullOrWhiteSpace(linkTarget))
        {
            return;
        }

        var relativePath = Path.GetRelativePath(sourceDirectoryPath, entry).Replace('\\', '/');
        symlinks.Add(new ImportSymlink(relativePath, linkTarget));
    }
}
