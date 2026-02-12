namespace ContainAI.Cli.Host;

internal interface IShellProfileFileSystem
{
    bool FileExists(string path);

    bool DirectoryExists(string path);

    IEnumerable<string> EnumerateFileSystemEntries(string path);

    Task<string> ReadAllTextAsync(string path, CancellationToken cancellationToken);

    Task WriteAllTextAsync(string path, string content, CancellationToken cancellationToken);

    void CreateDirectory(string path);

    void DeleteFile(string path);

    void DeleteDirectory(string path);
}
