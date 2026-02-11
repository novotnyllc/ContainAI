namespace ContainAI.Cli.Host;

internal static class TomlCommandFileWriteService
{
    public static TomlCommandResult WriteConfig(string filePath, string content)
    {
        try
        {
            var directory = Path.GetDirectoryName(filePath);
            if (string.IsNullOrWhiteSpace(directory))
            {
                return new TomlCommandResult(1, string.Empty, $"Error: Cannot determine config directory for file: {filePath}");
            }

            Directory.CreateDirectory(directory);
            TomlCommandUnixModeHelper.TrySetDirectoryMode(directory);

            var tempPath = Path.Combine(directory, $".config_{Guid.NewGuid():N}.tmp");
            try
            {
                File.WriteAllText(tempPath, content);
                TomlCommandUnixModeHelper.TrySetFileMode(tempPath);
                File.Move(tempPath, filePath, overwrite: true);
                TomlCommandUnixModeHelper.TrySetFileMode(filePath);
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
}
