namespace ContainAI.Cli.Host;

internal static class TomlCommandUnixModeHelper
{
    public static void TrySetDirectoryMode(string directory)
    {
        if (!OperatingSystem.IsLinux() && !OperatingSystem.IsMacOS())
        {
            return;
        }

        try
        {
            File.SetUnixFileMode(
                directory,
                UnixFileMode.UserRead |
                UnixFileMode.UserWrite |
                UnixFileMode.UserExecute);
        }
        catch (UnauthorizedAccessException ex)
        {
            _ = ex;
        }
        catch (IOException ex)
        {
            _ = ex;
        }
    }

    public static void TrySetFileMode(string path)
    {
        if (!OperatingSystem.IsLinux() && !OperatingSystem.IsMacOS())
        {
            return;
        }

        try
        {
            File.SetUnixFileMode(
                path,
                UnixFileMode.UserRead |
                UnixFileMode.UserWrite);
        }
        catch (UnauthorizedAccessException ex)
        {
            _ = ex;
        }
        catch (IOException ex)
        {
            _ = ex;
        }
    }
}
