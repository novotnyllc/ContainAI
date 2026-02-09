using System.Text.RegularExpressions;
using CsToml.Error;

namespace ContainAI.Cli.Host;

internal static partial class TomlCommandProcessor
{
    private static readonly TomlCommandFileIo FileIo = new();
    private static readonly TomlCommandParser Parser = new();
    private static readonly TomlCommandSerializer Serializer = new();
    private static readonly TomlCommandUpdater Updater = new();
    private static readonly TomlCommandValidator Validator = new(Parser);

    private static bool FileExists(string filePath) => FileIo.FileExists(filePath);

    private static TomlCommandResult WriteConfig(string filePath, string content)
        => FileIo.WriteConfig(filePath, content);

    private static TomlLoadResult LoadToml(string filePath, int missingFileExitCode, string? missingFileMessage)
    {
        if (!FileIo.FileExists(filePath))
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
            var content = FileIo.ReadAllText(filePath);
            var model = Parser.ParseTomlContent(content);
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

    private static bool TryReadText(string filePath, out string content, out string? error)
        => FileIo.TryReadText(filePath, out content, out error);

    private static TomlCommandResult SerializeAsJson(IReadOnlyDictionary<string, object?> table)
        => Serializer.SerializeAsJson(table);

    private static string SerializeJsonValue(object? value)
        => Serializer.SerializeJsonValue(value);

    private static string FormatValue(object? value)
        => Serializer.FormatValue(value);

    private static bool TryGetNestedValue(IReadOnlyDictionary<string, object?> table, string key, out object? value)
        => Parser.TryGetNestedValue(table, key, out value);

    private static object GetWorkspaceState(IReadOnlyDictionary<string, object?> table, string workspacePath)
        => Parser.GetWorkspaceState(table, workspacePath);

    private static string UpsertWorkspaceKey(string content, string workspacePath, string key, string value)
        => Updater.UpsertWorkspaceKey(content, workspacePath, key, value);

    private static string RemoveWorkspaceKey(string content, string workspacePath, string key)
        => Updater.RemoveWorkspaceKey(content, workspacePath, key);

    private static string UpsertGlobalKey(string content, string[] keyParts, string formattedValue)
        => Updater.UpsertGlobalKey(content, keyParts, formattedValue);

    private static string RemoveGlobalKey(string content, string[] keyParts)
        => Updater.RemoveGlobalKey(content, keyParts);

    private static string? FormatTomlValueForKey(string key, string value)
        => Validator.FormatTomlValueForKey(key, value);

    private static (bool Success, object? Value, string? Warning, string? Error) ValidateEnvSection(IReadOnlyDictionary<string, object?> table)
    {
        var result = Validator.ValidateEnvSection(table);
        return (result.Success, result.Value, result.Warning, result.Error);
    }

    private static (bool Success, object? Value, string? Error) ValidateAgentSection(IReadOnlyDictionary<string, object?> table, string sourceFile)
    {
        var result = Validator.ValidateAgentSection(table, sourceFile);
        return (result.Success, result.Value, result.Error);
    }

    [GeneratedRegex("^[a-zA-Z_][a-zA-Z0-9_]*$", RegexOptions.CultureInvariant)]
    private static partial Regex WorkspaceKeyRegexFactory();

    [GeneratedRegex("^[a-zA-Z_][a-zA-Z0-9_.]*$", RegexOptions.CultureInvariant)]
    private static partial Regex GlobalKeyRegexFactory();

    private sealed record TomlCommandArguments
    {
        public string FilePath { get; init; } = string.Empty;

        public string? KeyOrExistsArg { get; init; }

        public string? WorkspacePathOrUnsetPath { get; init; }

        public string? WorkspaceKey { get; init; }

        public string? Value { get; init; }
    }
}
