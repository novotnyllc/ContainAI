namespace ContainAI.Cli.Host.Importing.Symlinks;

internal interface IImportSymlinkScanner
{
    IReadOnlyList<ImportSymlink> CollectSymlinksForRelink(string sourceDirectoryPath);
}
