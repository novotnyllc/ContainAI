namespace ContainAI.Cli.Host;

internal readonly record struct TomlLoadResult(
    bool Success,
    TomlCommandResult Result,
    IReadOnlyDictionary<string, object?>? Table);

internal readonly record struct TomlEnvValidationResult(
    bool Success,
    object? Value,
    string? Warning,
    string? Error);

internal readonly record struct TomlAgentValidationResult(
    bool Success,
    object? Value,
    string? Error);

internal interface ITomlCommandFileIo
{
    bool FileExists(string filePath);

    string ReadAllText(string filePath);

    bool TryReadText(string filePath, out string content, out string? error);

    TomlCommandResult WriteConfig(string filePath, string content);
}

internal interface ITomlCommandParser
{
    IReadOnlyDictionary<string, object?> ParseTomlContent(string content);

    bool TryGetNestedValue(IReadOnlyDictionary<string, object?> table, string key, out object? value);

    object GetWorkspaceState(IReadOnlyDictionary<string, object?> table, string workspacePath);

    bool TryGetTable(object? value, out IReadOnlyDictionary<string, object?> table);

    bool TryGetList(object? value, out IReadOnlyList<object?> list);

    string GetValueTypeName(object? value);
}

internal interface ITomlCommandSerializer
{
    TomlCommandResult SerializeAsJson(IReadOnlyDictionary<string, object?> table);

    string SerializeJsonValue(object? value);

    string FormatValue(object? value);
}

internal interface ITomlCommandUpdater
{
    string UpsertWorkspaceKey(string content, string workspacePath, string key, string value);

    string RemoveWorkspaceKey(string content, string workspacePath, string key);

    string UpsertGlobalKey(string content, string[] keyParts, string formattedValue);

    string RemoveGlobalKey(string content, string[] keyParts);
}

internal interface ITomlCommandValidator
{
    TomlEnvValidationResult ValidateEnvSection(IReadOnlyDictionary<string, object?> table);

    TomlAgentValidationResult ValidateAgentSection(IReadOnlyDictionary<string, object?> table, string sourceFile);

    string? FormatTomlValueForKey(string key, string value);
}
