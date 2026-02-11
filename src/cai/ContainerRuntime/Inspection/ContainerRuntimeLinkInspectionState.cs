namespace ContainAI.Cli.Host.ContainerRuntime.Inspection;

internal enum ContainerRuntimeLinkInspectionState
{
    Ok,
    BrokenDanglingSymlink,
    BrokenWrongTargetSymlink,
    BrokenDirectoryReplaceable,
    DirectoryConflict,
    BrokenFileReplaceable,
    Missing,
}
