using ContainAI.Cli.Host.RuntimeSupport.Paths;

namespace ContainAI.Cli.Host.Importing.Symlinks;

internal interface IImportSymlinkRelinkOperationBuilder
{
    IReadOnlyList<ImportSymlinkRelinkOperation> Build(
        string sourceDirectoryPath,
        string targetRelativePath,
        IReadOnlyList<ImportSymlink> symlinks);
}
