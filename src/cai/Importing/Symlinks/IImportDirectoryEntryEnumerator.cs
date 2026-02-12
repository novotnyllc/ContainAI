namespace ContainAI.Cli.Host.Importing.Symlinks;

internal interface IImportDirectoryEntryEnumerator
{
    bool TryEnumerateEntries(string directory, out IEnumerable<string> entries);
}
