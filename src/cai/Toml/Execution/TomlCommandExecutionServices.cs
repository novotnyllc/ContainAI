using CsToml.Error;

namespace ContainAI.Cli.Host;

internal sealed class TomlCommandExecutionServices
{
    private readonly ITomlCommandFileIo fileIo;
    private readonly ITomlCommandParser parser;
    private readonly ITomlCommandSerializer serializer;
    private readonly ITomlCommandUpdater updater;
    private readonly ITomlCommandValidator validator;

    public TomlCommandExecutionServices(
        ITomlCommandFileIo fileIo,
        ITomlCommandParser parser,
        ITomlCommandSerializer serializer,
        ITomlCommandUpdater updater,
        ITomlCommandValidator validator)
    {
        this.fileIo = fileIo;
        this.parser = parser;
        this.serializer = serializer;
        this.updater = updater;
        this.validator = validator;
    }

    public bool FileExists(string filePath) => fileIo.FileExists(filePath);

    public TomlCommandResult WriteConfig(string filePath, string content)
        => fileIo.WriteConfig(filePath, content);

    public bool TryReadText(string filePath, out string content, out string? error)
        => fileIo.TryReadText(filePath, out content, out error);

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

    public bool TryGetNestedValue(IReadOnlyDictionary<string, object?> table, string key, out object? value)
        => parser.TryGetNestedValue(table, key, out value);

    public object GetWorkspaceState(IReadOnlyDictionary<string, object?> table, string workspacePath)
        => parser.GetWorkspaceState(table, workspacePath);

    public TomlCommandResult SerializeAsJson(IReadOnlyDictionary<string, object?> table)
        => serializer.SerializeAsJson(table);

    public string SerializeJsonValue(object? value)
        => serializer.SerializeJsonValue(value);

    public string FormatValue(object? value)
        => serializer.FormatValue(value);

    public string UpsertWorkspaceKey(string content, string workspacePath, string key, string value)
        => updater.UpsertWorkspaceKey(content, workspacePath, key, value);

    public string RemoveWorkspaceKey(string content, string workspacePath, string key)
        => updater.RemoveWorkspaceKey(content, workspacePath, key);

    public string UpsertGlobalKey(string content, string[] keyParts, string formattedValue)
        => updater.UpsertGlobalKey(content, keyParts, formattedValue);

    public string RemoveGlobalKey(string content, string[] keyParts)
        => updater.RemoveGlobalKey(content, keyParts);

    public string? FormatTomlValueForKey(string key, string value)
        => validator.FormatTomlValueForKey(key, value);

    public TomlEnvValidationResult ValidateEnvSection(IReadOnlyDictionary<string, object?> table)
        => validator.ValidateEnvSection(table);

    public TomlAgentValidationResult ValidateAgentSection(IReadOnlyDictionary<string, object?> table, string sourceFile)
        => validator.ValidateAgentSection(table, sourceFile);
}
