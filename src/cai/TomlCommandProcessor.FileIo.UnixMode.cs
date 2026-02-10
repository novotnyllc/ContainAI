namespace ContainAI.Cli.Host;

internal sealed partial class TomlCommandFileIo
{
    private static void TrySetDirectoryMode(string directory)
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

    private static void TrySetFileMode(string path)
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
