namespace ContainAI.Cli.Host.Devcontainer.Inspection;

internal interface IDevcontainerSymlinkInspector
{
    bool IsSymlink(string path);
}
