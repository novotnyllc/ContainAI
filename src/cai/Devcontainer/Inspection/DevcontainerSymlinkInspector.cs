using ContainAI.Cli.Host.Devcontainer.ProcessExecution;

namespace ContainAI.Cli.Host.Devcontainer.Inspection;

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
