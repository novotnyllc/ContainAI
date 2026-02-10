namespace ContainAI.Cli.Host;

internal sealed partial class InstallDeploymentService
{
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
