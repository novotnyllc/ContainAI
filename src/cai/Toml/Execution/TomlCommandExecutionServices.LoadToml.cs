using CsToml.Error;

namespace ContainAI.Cli.Host;

internal sealed partial class TomlCommandExecutionServices
{
    public TomlLoadResult LoadToml(string filePath, int missingFileExitCode, string? missingFileMessage)
    {
        if (!fileIo.FileExists(filePath))
        {
            if (missingFileMessage is not null)
            {
                return new TomlLoadResult(true, new TomlCommandResult(0, missingFileMessage, string.Empty), null);
            }

            return new TomlLoadResult(
                false,
                new TomlCommandResult(missingFileExitCode, string.Empty, $"Error: File not found: {filePath}"),
                null);
        }

        try
        {
            var content = fileIo.ReadAllText(filePath);
            var model = parser.ParseTomlContent(content);
            return new TomlLoadResult(true, new TomlCommandResult(0, string.Empty, string.Empty), model);
        }
        catch (UnauthorizedAccessException)
        {
            return new TomlLoadResult(false, new TomlCommandResult(1, string.Empty, $"Error: Permission denied: {filePath}"), null);
        }
        catch (IOException ex)
        {
            return new TomlLoadResult(false, new TomlCommandResult(1, string.Empty, $"Error: Cannot read file: {ex.Message}"), null);
        }
        catch (CsTomlException ex)
        {
            return new TomlLoadResult(false, new TomlCommandResult(1, string.Empty, $"Error: Invalid TOML: {ex.Message}"), null);
        }
        catch (InvalidOperationException ex)
        {
            return new TomlLoadResult(false, new TomlCommandResult(1, string.Empty, $"Error: Invalid TOML: {ex.Message}"), null);
        }
        catch (ArgumentException ex)
        {
            return new TomlLoadResult(false, new TomlCommandResult(1, string.Empty, $"Error: Invalid TOML: {ex.Message}"), null);
        }
        catch (FormatException ex)
        {
            return new TomlLoadResult(false, new TomlCommandResult(1, string.Empty, $"Error: Invalid TOML: {ex.Message}"), null);
        }
    }
}
