namespace ContainAI.Cli.Host;

internal sealed partial class InstallDeploymentService
{
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
}
