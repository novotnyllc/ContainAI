namespace ContainAI.Cli.Host.Importing.Symlinks;

internal interface IPosixPathService
{
    bool IsPathWithinDirectory(string path, string directory);

    string NormalizePosixPath(string path);

    string ComputeRelativePosixPath(string fromDirectory, string toPath);
}
