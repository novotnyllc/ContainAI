namespace ContainAI.Cli.Host;

internal interface IDevcontainerSymlinkInspector
{
    bool IsSymlink(string path);
}

internal sealed class DevcontainerSymlinkInspector(DevcontainerFileSystem fileSystem) : IDevcontainerSymlinkInspector
{
    public bool IsSymlink(string path)
    {
        try
        {
            var attributes = fileSystem.GetAttributes(path);
            return (attributes & FileAttributes.ReparsePoint) != 0;
        }
        catch (IOException)
        {
            return false;
        }
        catch (UnauthorizedAccessException)
        {
            return false;
        }
        catch (ArgumentException)
        {
            return false;
        }
        catch (NotSupportedException)
        {
            return false;
        }
    }
}
