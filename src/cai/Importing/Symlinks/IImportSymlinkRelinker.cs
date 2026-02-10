namespace ContainAI.Cli.Host.Importing.Symlinks;

internal interface IImportSymlinkRelinker
{
    Task<int> RelinkImportedDirectorySymlinksAsync(
        string volume,
        string sourceDirectoryPath,
        string targetRelativePath,
        CancellationToken cancellationToken);
}
