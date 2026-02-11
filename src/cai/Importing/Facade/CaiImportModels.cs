namespace ContainAI.Cli.Host;

internal readonly record struct ImportAdditionalPath(
    string SourcePath,
    string TargetPath,
    bool IsDirectory,
    bool ApplyPrivFilter);

internal readonly record struct ImportSymlink(
    string RelativePath,
    string Target);
