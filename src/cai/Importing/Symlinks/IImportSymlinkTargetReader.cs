namespace ContainAI.Cli.Host.Importing.Symlinks;

internal interface IImportSymlinkTargetReader
{
    string? ReadSymlinkTarget(string path);
}
