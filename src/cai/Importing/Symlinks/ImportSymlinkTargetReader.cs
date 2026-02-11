namespace ContainAI.Cli.Host.Importing.Symlinks;

internal interface IImportSymlinkTargetReader
{
    string? ReadSymlinkTarget(string path);
}

internal sealed class ImportSymlinkTargetReader : IImportSymlinkTargetReader
{
    public string? ReadSymlinkTarget(string path)
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
