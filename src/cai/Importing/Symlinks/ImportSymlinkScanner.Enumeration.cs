namespace ContainAI.Cli.Host.Importing.Symlinks;

internal sealed partial class ImportSymlinkScanner
{
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
}
