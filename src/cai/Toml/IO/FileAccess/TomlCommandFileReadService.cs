namespace ContainAI.Cli.Host;

internal static class TomlCommandFileReadService
{
    public static bool TryReadText(string filePath, out string content, out string? error)
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
}
