namespace ContainAI.Cli.Host.Importing.Symlinks;

internal interface IImportDirectoryEntryEnumerator
{
    bool TryEnumerateEntries(string directory, out IEnumerable<string> entries);
}

internal sealed class ImportDirectoryEntryEnumerator : IImportDirectoryEntryEnumerator
{
    public bool TryEnumerateEntries(string directory, out IEnumerable<string> entries)
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
}
