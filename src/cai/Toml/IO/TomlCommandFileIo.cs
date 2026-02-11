namespace ContainAI.Cli.Host;

internal sealed class TomlCommandFileIo : ITomlCommandFileIo
{
    public bool FileExists(string filePath) => File.Exists(filePath);

    public string ReadAllText(string filePath) => File.ReadAllText(filePath);

    public bool TryReadText(string filePath, out string content, out string? error)
    {
        content = string.Empty;
        error = null;

        if (!File.Exists(filePath))
        {
            return true;
        }

        try
        {
            content = File.ReadAllText(filePath);
            return true;
        }
        catch (UnauthorizedAccessException ex)
        {
            error = $"Error: Cannot read file: {ex.Message}";
            return false;
        }
        catch (IOException ex)
        {
            error = $"Error: Cannot read file: {ex.Message}";
            return false;
        }
        catch (ArgumentException ex)
        {
            error = $"Error: Cannot read file: {ex.Message}";
            return false;
        }
    }

    public TomlCommandResult WriteConfig(string filePath, string content)
    {
        try
        {
            var directory = Path.GetDirectoryName(filePath);
            if (string.IsNullOrWhiteSpace(directory))
            {
                return new TomlCommandResult(1, string.Empty, $"Error: Cannot determine config directory for file: {filePath}");
            }

            Directory.CreateDirectory(directory);
            TrySetDirectoryMode(directory);

            var tempPath = Path.Combine(directory, $".config_{Guid.NewGuid():N}.tmp");
            try
            {
                File.WriteAllText(tempPath, content);
                TrySetFileMode(tempPath);
                File.Move(tempPath, filePath, overwrite: true);
                TrySetFileMode(filePath);
                return new TomlCommandResult(0, string.Empty, string.Empty);
            }
            finally
            {
                if (File.Exists(tempPath))
                {
                    File.Delete(tempPath);
                }
            }
        }
        catch (UnauthorizedAccessException ex)
        {
            return new TomlCommandResult(1, string.Empty, $"Error: Cannot write file: {ex.Message}");
        }
        catch (IOException ex)
        {
            return new TomlCommandResult(1, string.Empty, $"Error: Cannot write file: {ex.Message}");
        }
        catch (ArgumentException ex)
        {
            return new TomlCommandResult(1, string.Empty, $"Error: Cannot write file: {ex.Message}");
        }
        catch (NotSupportedException ex)
        {
            return new TomlCommandResult(1, string.Empty, $"Error: Cannot write file: {ex.Message}");
        }
    }

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
