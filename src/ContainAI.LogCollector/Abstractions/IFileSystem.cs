using System.IO;

namespace ContainAI.LogCollector.Abstractions;

public interface IFileSystem
{
    void CreateDirectory(string path);
    bool FileExists(string path);
    void DeleteFile(string path);
    Stream OpenAppend(string path);
}
