namespace ContainAI.Cli.Host;

internal static class InstallDeploymentService
{
    public static InstallDeploymentResult Deploy(string sourceExecutablePath, string installDir, string binDir)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(sourceExecutablePath);
        ArgumentException.ThrowIfNullOrWhiteSpace(installDir);
        ArgumentException.ThrowIfNullOrWhiteSpace(binDir);

        if (!File.Exists(sourceExecutablePath))
        {
            throw new FileNotFoundException("Source executable was not found.", sourceExecutablePath);
        }

        Directory.CreateDirectory(installDir);
        Directory.CreateDirectory(binDir);

        var installedExecutablePath = Path.Combine(installDir, "cai");
        File.Copy(sourceExecutablePath, installedExecutablePath, overwrite: true);
        EnsureExecutable(installedExecutablePath);

        var wrapperPath = Path.Combine(binDir, "cai");
        CreateExecutableLink(installedExecutablePath, wrapperPath);

        var dockerProxyPath = Path.Combine(binDir, "containai-docker");
        CreateExecutableLink(installedExecutablePath, dockerProxyPath);

        return new InstallDeploymentResult(installedExecutablePath, wrapperPath, dockerProxyPath);
    }

    private static void EnsureExecutable(string filePath)
    {
        if (!(OperatingSystem.IsLinux() || OperatingSystem.IsMacOS()))
        {
            return;
        }

        try
        {
            File.SetUnixFileMode(
                filePath,
                UnixFileMode.UserRead |
                UnixFileMode.UserWrite |
                UnixFileMode.UserExecute |
                UnixFileMode.GroupRead |
                UnixFileMode.GroupExecute |
                UnixFileMode.OtherRead |
                UnixFileMode.OtherExecute);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or NotSupportedException)
        {
            return;
        }
    }

    private static void CreateExecutableLink(string sourcePath, string destinationPath)
    {
        if (File.Exists(destinationPath) || Directory.Exists(destinationPath))
        {
            File.Delete(destinationPath);
        }

        try
        {
            if (OperatingSystem.IsWindows())
            {
                File.Copy(sourcePath, destinationPath, overwrite: true);
            }
            else
            {
                File.CreateSymbolicLink(destinationPath, sourcePath);
            }
        }
        catch (IOException)
        {
            File.Copy(sourcePath, destinationPath, overwrite: true);
        }
        catch (UnauthorizedAccessException)
        {
            File.Copy(sourcePath, destinationPath, overwrite: true);
        }
        catch (NotSupportedException)
        {
            File.Copy(sourcePath, destinationPath, overwrite: true);
        }

        EnsureExecutable(destinationPath);
    }
}

internal sealed record InstallDeploymentResult(
    string InstalledExecutablePath,
    string WrapperPath,
    string DockerProxyPath);
