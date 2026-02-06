using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;
using Tomlyn;
using Tomlyn.Model;

namespace ContainAI.Cli.Host;

internal sealed record TomlCommandResult(int ExitCode, string StandardOutput, string StandardError);

internal static partial class TomlCommandProcessor
{
    private static readonly Regex WorkspaceKeyRegex = WorkspaceKeyRegexFactory();
    private static readonly Regex GlobalKeyRegex = GlobalKeyRegexFactory();

    public static TomlCommandResult Execute(IReadOnlyList<string> args)
    {
        if (!TryParseArguments(args, out var parsed, out var parseError))
        {
            return new TomlCommandResult(1, string.Empty, parseError);
        }

        return parsed.Mode switch
        {
            TomlMode.Key => ExecuteKey(parsed),
            TomlMode.Json => ExecuteJson(parsed),
            TomlMode.Exists => ExecuteExists(parsed),
            TomlMode.Env => ExecuteEnv(parsed),
            TomlMode.GetWorkspace => ExecuteGetWorkspace(parsed),
            TomlMode.SetWorkspaceKey => ExecuteSetWorkspaceKey(parsed),
            TomlMode.UnsetWorkspaceKey => ExecuteUnsetWorkspaceKey(parsed),
            TomlMode.SetKey => ExecuteSetKey(parsed),
            TomlMode.UnsetKey => ExecuteUnsetKey(parsed),
            TomlMode.EmitAgents => ExecuteEmitAgents(parsed),
            _ => new TomlCommandResult(1, string.Empty, "Error: Unsupported toml mode"),
        };
    }

    private static TomlCommandResult ExecuteKey(TomlCommandArguments parsed)
    {
        var load = LoadToml(parsed.FilePath!, missingFileExitCode: 1, missingFileMessage: null);
        if (!load.Success)
        {
            return load.Result;
        }

        var key = parsed.KeyOrExistsArg!;
        if (!TryGetNestedValue(load.Table!, key, out var value))
        {
            return new TomlCommandResult(0, string.Empty, string.Empty);
        }

        return new TomlCommandResult(0, FormatValue(value), string.Empty);
    }

    private static TomlCommandResult ExecuteJson(TomlCommandArguments parsed)
    {
        var load = LoadToml(parsed.FilePath!, missingFileExitCode: 1, missingFileMessage: null);
        if (!load.Success)
        {
            return load.Result;
        }

        return SerializeAsJson(load.Table!);
    }

    private static TomlCommandResult ExecuteExists(TomlCommandArguments parsed)
    {
        var load = LoadToml(parsed.FilePath!, missingFileExitCode: 1, missingFileMessage: null);
        if (!load.Success)
        {
            return load.Result;
        }

        return TryGetNestedValue(load.Table!, parsed.KeyOrExistsArg!, out _)
            ? new TomlCommandResult(0, string.Empty, string.Empty)
            : new TomlCommandResult(1, string.Empty, string.Empty);
    }

    private static TomlCommandResult ExecuteEnv(TomlCommandArguments parsed)
    {
        var load = LoadToml(parsed.FilePath!, missingFileExitCode: 1, missingFileMessage: null);
        if (!load.Success)
        {
            return load.Result;
        }

        var result = ValidateEnvSection(load.Table!);
        if (!result.Success)
        {
            return new TomlCommandResult(1, string.Empty, result.Error!);
        }

        var serialized = SerializeJsonValue(result.Value);
        return new TomlCommandResult(0, serialized, result.Warning ?? string.Empty);
    }

    private static TomlCommandResult ExecuteGetWorkspace(TomlCommandArguments parsed)
    {
        var path = parsed.WorkspacePathOrUnsetPath!;
        var filePath = parsed.FilePath!;

        if (!File.Exists(filePath))
        {
            return new TomlCommandResult(0, "{}", string.Empty);
        }

        var load = LoadToml(filePath, missingFileExitCode: 0, missingFileMessage: "{}");
        if (!load.Success)
        {
            return load.Result;
        }

        var workspaceState = GetWorkspaceState(load.Table!, path);
        return new TomlCommandResult(0, SerializeJsonValue(workspaceState), string.Empty);
    }

    private static TomlCommandResult ExecuteSetWorkspaceKey(TomlCommandArguments parsed)
    {
        var wsPath = parsed.WorkspacePathOrUnsetPath!;
        var key = parsed.WorkspaceKey!;
        var value = parsed.Value!;

        if (!WorkspaceKeyRegex.IsMatch(key))
        {
            return new TomlCommandResult(1, string.Empty, $"Error: Invalid key name: {key}");
        }

        if (!wsPath.StartsWith("/", StringComparison.Ordinal))
        {
            return new TomlCommandResult(1, string.Empty, $"Error: Workspace path must be absolute: {wsPath}");
        }

        if (wsPath.IndexOf('\0') >= 0)
        {
            return new TomlCommandResult(1, string.Empty, "Error: Workspace path contains null byte");
        }

        if (wsPath.IndexOf('\n') >= 0 || wsPath.IndexOf('\r') >= 0)
        {
            return new TomlCommandResult(1, string.Empty, "Error: Workspace path contains newline");
        }

        var contentRead = TryReadText(parsed.FilePath!, out var content, out var readError);
        if (!contentRead)
        {
            return new TomlCommandResult(1, string.Empty, readError!);
        }

        var updated = UpsertWorkspaceKey(content, wsPath, key, value);
        return WriteConfig(parsed.FilePath!, updated);
    }

    private static TomlCommandResult ExecuteUnsetWorkspaceKey(TomlCommandArguments parsed)
    {
        var wsPath = parsed.WorkspacePathOrUnsetPath!;
        var key = parsed.WorkspaceKey!;

        if (!WorkspaceKeyRegex.IsMatch(key))
        {
            return new TomlCommandResult(1, string.Empty, $"Error: Invalid key name: {key}");
        }

        if (!wsPath.StartsWith("/", StringComparison.Ordinal))
        {
            return new TomlCommandResult(1, string.Empty, $"Error: Workspace path must be absolute: {wsPath}");
        }

        if (!File.Exists(parsed.FilePath!))
        {
            return new TomlCommandResult(0, string.Empty, string.Empty);
        }

        var contentRead = TryReadText(parsed.FilePath!, out var content, out var readError);
        if (!contentRead)
        {
            return new TomlCommandResult(1, string.Empty, readError!);
        }

        var updated = RemoveWorkspaceKey(content, wsPath, key);
        return WriteConfig(parsed.FilePath!, updated);
    }

    private static TomlCommandResult ExecuteSetKey(TomlCommandArguments parsed)
    {
        var key = parsed.KeyOrExistsArg!;
        var value = parsed.Value!;

        if (!GlobalKeyRegex.IsMatch(key))
        {
            return new TomlCommandResult(1, string.Empty, $"Error: Invalid key name: {key}");
        }

        var parts = key.Split('.', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (parts.Length == 0)
        {
            return new TomlCommandResult(1, string.Empty, $"Error: Invalid key name: {key}");
        }

        if (parts.Length > 2)
        {
            return new TomlCommandResult(1, string.Empty, $"Error: Key nesting too deep (max 2 levels): {key}");
        }

        var formattedValue = FormatTomlValueForKey(key, value);
        if (formattedValue is null)
        {
            return new TomlCommandResult(1, string.Empty, $"Error: Invalid value for key '{key}'");
        }

        var contentRead = TryReadText(parsed.FilePath!, out var content, out var readError);
        if (!contentRead)
        {
            return new TomlCommandResult(1, string.Empty, readError!);
        }

        var updated = UpsertGlobalKey(content, parts, formattedValue);
        return WriteConfig(parsed.FilePath!, updated);
    }

    private static TomlCommandResult ExecuteUnsetKey(TomlCommandArguments parsed)
    {
        var key = parsed.KeyOrExistsArg!;
        if (!GlobalKeyRegex.IsMatch(key))
        {
            return new TomlCommandResult(1, string.Empty, $"Error: Invalid key name: {key}");
        }

        if (!File.Exists(parsed.FilePath!))
        {
            return new TomlCommandResult(0, string.Empty, string.Empty);
        }

        var parts = key.Split('.', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (parts.Length == 0)
        {
            return new TomlCommandResult(1, string.Empty, $"Error: Invalid key name: {key}");
        }

        var contentRead = TryReadText(parsed.FilePath!, out var content, out var readError);
        if (!contentRead)
        {
            return new TomlCommandResult(1, string.Empty, readError!);
        }

        var updated = RemoveGlobalKey(content, parts);
        return WriteConfig(parsed.FilePath!, updated);
    }

    private static TomlCommandResult ExecuteEmitAgents(TomlCommandArguments parsed)
    {
        var load = LoadToml(parsed.FilePath!, missingFileExitCode: 1, missingFileMessage: null);
        if (!load.Success)
        {
            return load.Result;
        }

        var validation = ValidateAgentSection(load.Table!, parsed.FilePath!);
        if (!validation.Success)
        {
            return new TomlCommandResult(1, string.Empty, validation.Error!);
        }

        return new TomlCommandResult(0, SerializeJsonValue(validation.Value), string.Empty);
    }

    private static TomlCommandResult WriteConfig(string filePath, string content)
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
        catch (Exception ex)
        {
            return new TomlCommandResult(1, string.Empty, $"Error: Cannot write file: {ex.Message}");
        }
    }

    private static (bool Success, TomlCommandResult Result, TomlTable? Table) LoadToml(string filePath, int missingFileExitCode, string? missingFileMessage)
    {
        if (!File.Exists(filePath))
        {
            if (missingFileMessage is not null)
            {
                return (true, new TomlCommandResult(0, missingFileMessage, string.Empty), null);
            }

            return (false, new TomlCommandResult(missingFileExitCode, string.Empty, $"Error: File not found: {filePath}"), null);
        }

        try
        {
            var content = File.ReadAllText(filePath);
            if (Toml.ToModel(content) is not TomlTable model)
            {
                return (false, new TomlCommandResult(1, string.Empty, "Error: Failed to parse TOML model."), null);
            }

            return (true, new TomlCommandResult(0, string.Empty, string.Empty), model);
        }
        catch (UnauthorizedAccessException)
        {
            return (false, new TomlCommandResult(1, string.Empty, $"Error: Permission denied: {filePath}"), null);
        }
        catch (IOException ex)
        {
            return (false, new TomlCommandResult(1, string.Empty, $"Error: Cannot read file: {ex.Message}"), null);
        }
        catch (Exception ex)
        {
            return (false, new TomlCommandResult(1, string.Empty, $"Error: Invalid TOML: {ex.Message}"), null);
        }
    }

    private static bool TryReadText(string filePath, out string content, out string? error)
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
        catch (Exception ex)
        {
            error = $"Error: Cannot read file: {ex.Message}";
            return false;
        }
    }

    private static TomlCommandResult SerializeAsJson(TomlTable table)
    {
        try
        {
            return new TomlCommandResult(0, SerializeJsonValue(table), string.Empty);
        }
        catch (Exception ex)
        {
            return new TomlCommandResult(1, string.Empty, $"Error: Cannot serialize config: {ex.Message}");
        }
    }

    private static string SerializeJsonValue(object? value)
    {
        var normalized = NormalizeTomlValue(value);
        var builder = new StringBuilder();
        WriteJsonValue(builder, normalized);
        return builder.ToString();
    }

    private static object? NormalizeTomlValue(object? value)
    {
        return value switch
        {
            null => null,
            TomlTable table => table.ToDictionary(static pair => pair.Key, static pair => NormalizeTomlValue(pair.Value), StringComparer.Ordinal),
            TomlTableArray tableArray => tableArray.Select(NormalizeTomlValue).ToList(),
            IList<object?> list => list.Select(NormalizeTomlValue).ToList(),
            DateTime dateTime => dateTime.ToString("O", CultureInfo.InvariantCulture),
            DateTimeOffset dateTimeOffset => dateTimeOffset.ToString("O", CultureInfo.InvariantCulture),
            _ => value,
        };
    }

    private static void WriteJsonValue(StringBuilder builder, object? value)
    {
        switch (value)
        {
            case null:
                builder.Append("null");
                return;
            case bool boolValue:
                builder.Append(boolValue ? "true" : "false");
                return;
            case byte or sbyte or short or ushort or int or uint or long or ulong or float or double or decimal:
                builder.Append(Convert.ToString(value, CultureInfo.InvariantCulture));
                return;
            case string stringValue:
                WriteJsonString(builder, stringValue);
                return;
            case IDictionary<string, object?> dictionary:
                builder.Append('{');
                var firstProperty = true;
                foreach (var pair in dictionary)
                {
                    if (!firstProperty)
                    {
                        builder.Append(',');
                    }

                    firstProperty = false;
                    WriteJsonString(builder, pair.Key);
                    builder.Append(':');
                    WriteJsonValue(builder, pair.Value);
                }

                builder.Append('}');
                return;
            case IList<object?> list:
                builder.Append('[');
                for (var index = 0; index < list.Count; index++)
                {
                    if (index > 0)
                    {
                        builder.Append(',');
                    }

                    WriteJsonValue(builder, list[index]);
                }

                builder.Append(']');
                return;
            default:
                WriteJsonString(builder, Convert.ToString(value, CultureInfo.InvariantCulture) ?? string.Empty);
                return;
        }
    }

    private static void WriteJsonString(StringBuilder builder, string value)
    {
        builder.Append('"');
        foreach (var ch in value)
        {
            switch (ch)
            {
                case '"':
                    builder.Append("\\\"");
                    break;
                case '\\':
                    builder.Append("\\\\");
                    break;
                case '\b':
                    builder.Append("\\b");
                    break;
                case '\f':
                    builder.Append("\\f");
                    break;
                case '\n':
                    builder.Append("\\n");
                    break;
                case '\r':
                    builder.Append("\\r");
                    break;
                case '\t':
                    builder.Append("\\t");
                    break;
                default:
                    if (ch < 0x20)
                    {
                        builder.Append("\\u");
                        builder.Append(((int)ch).ToString("x4", CultureInfo.InvariantCulture));
                    }
                    else
                    {
                        builder.Append(ch);
                    }

                    break;
            }
        }

        builder.Append('"');
    }

    private static string FormatValue(object? value)
    {
        return value switch
        {
            null => string.Empty,
            bool boolValue => boolValue ? "true" : "false",
            byte or sbyte or short or ushort or int or uint or long or ulong => Convert.ToString(value, CultureInfo.InvariantCulture) ?? string.Empty,
            float or double or decimal => Convert.ToString(value, CultureInfo.InvariantCulture) ?? string.Empty,
            string stringValue => stringValue,
            _ => SerializeJsonValue(value),
        };
    }

    private static bool TryGetNestedValue(TomlTable table, string key, out object? value)
    {
        var parts = key.Split('.', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (parts.Length == 0)
        {
            value = null;
            return false;
        }

        object? current = table;
        foreach (var part in parts)
        {
            if (current is not TomlTable currentTable || !currentTable.TryGetValue(part, out current))
            {
                value = null;
                return false;
            }
        }

        value = current;
        return true;
    }

    private static object GetWorkspaceState(TomlTable table, string workspacePath)
    {
        if (!table.TryGetValue("workspace", out var workspaceObj) || workspaceObj is not TomlTable workspaceTable)
        {
            return new Dictionary<string, object?>(StringComparer.Ordinal);
        }

        if (!workspaceTable.TryGetValue(workspacePath, out var entry) || entry is not TomlTable workspaceState)
        {
            return new Dictionary<string, object?>(StringComparer.Ordinal);
        }

        return workspaceState;
    }

    private static string UpsertWorkspaceKey(string content, string workspacePath, string key, string value)
    {
        var header = $"[workspace.\"{EscapeTomlKey(workspacePath)}\"]";
        var keyLine = $"{key} = {FormatTomlString(value)}";

        var lines = SplitLines(content);
        var newLines = new List<string>(lines.Count + 4);
        var inTargetSection = false;
        var foundSection = false;
        var keyUpdated = false;
        var lastContentIndex = -1;

        for (var index = 0; index < lines.Count; index++)
        {
            var line = lines[index];
            var trimmed = line.Trim();

            if (IsTargetHeader(trimmed, header))
            {
                inTargetSection = true;
                foundSection = true;
                newLines.Add(line);
                lastContentIndex = newLines.Count - 1;
                continue;
            }

            if (inTargetSection && IsAnyTableHeader(trimmed))
            {
                if (!keyUpdated)
                {
                    var insertPos = Math.Clamp(lastContentIndex + 1, 0, newLines.Count);
                    newLines.Insert(insertPos, keyLine);
                    keyUpdated = true;
                }

                inTargetSection = false;
            }

            if (inTargetSection && Regex.IsMatch(trimmed, $"^{Regex.Escape(key)}\\s*=", RegexOptions.CultureInvariant))
            {
                newLines.Add(keyLine);
                lastContentIndex = newLines.Count - 1;
                keyUpdated = true;
                continue;
            }

            newLines.Add(line);
            if (inTargetSection && trimmed.Length > 0)
            {
                lastContentIndex = newLines.Count - 1;
            }
        }

        if (inTargetSection && !keyUpdated)
        {
            var insertPos = Math.Clamp(lastContentIndex + 1, 0, newLines.Count);
            newLines.Insert(insertPos, keyLine);
            keyUpdated = true;
        }

        if (!foundSection)
        {
            if (newLines.Count > 0 && newLines.Any(static line => !string.IsNullOrWhiteSpace(line)))
            {
                newLines.Add(string.Empty);
            }

            newLines.Add(header);
            newLines.Add(keyLine);
        }

        return NormalizeOutputContent(newLines);
    }

    private static string RemoveWorkspaceKey(string content, string workspacePath, string key)
    {
        var header = $"[workspace.\"{EscapeTomlKey(workspacePath)}\"]";
        var lines = SplitLines(content);
        var newLines = new List<string>(lines.Count);

        var inTargetSection = false;
        var sectionStart = -1;
        var sectionEnd = -1;

        foreach (var line in lines)
        {
            var trimmed = line.Trim();
            if (IsTargetHeader(trimmed, header))
            {
                inTargetSection = true;
                sectionStart = newLines.Count;
                newLines.Add(line);
                continue;
            }

            if (inTargetSection && IsAnyTableHeader(trimmed))
            {
                sectionEnd = newLines.Count;
                inTargetSection = false;
            }

            if (inTargetSection && Regex.IsMatch(trimmed, $"^{Regex.Escape(key)}\\s*=", RegexOptions.CultureInvariant))
            {
                continue;
            }

            newLines.Add(line);
        }

        if (inTargetSection)
        {
            sectionEnd = newLines.Count;
        }

        if (sectionStart >= 0 && sectionEnd > sectionStart && !SectionHasContent(newLines, sectionStart + 1, sectionEnd))
        {
            newLines.RemoveRange(sectionStart, sectionEnd - sectionStart);
            while (newLines.Count > 0 && string.IsNullOrWhiteSpace(newLines[^1]))
            {
                newLines.RemoveAt(newLines.Count - 1);
            }
        }

        return NormalizeOutputContent(newLines);
    }

    private static string UpsertGlobalKey(string content, string[] keyParts, string formattedValue)
    {
        var lines = SplitLines(content);
        var newLines = new List<string>(lines.Count + 3);
        var keyLine = $"{keyParts[^1]} = {formattedValue}";

        if (keyParts.Length == 1)
        {
            var keyUpdated = false;
            var inTable = false;

            foreach (var line in lines)
            {
                var trimmed = line.Trim();
                if (IsAnyTableHeader(trimmed))
                {
                    inTable = true;
                    if (!keyUpdated)
                    {
                        newLines.Add(keyLine);
                        keyUpdated = true;
                    }

                    newLines.Add(line);
                    continue;
                }

                if (!inTable && Regex.IsMatch(trimmed, $"^{Regex.Escape(keyParts[0])}\\s*=", RegexOptions.CultureInvariant))
                {
                    newLines.Add(keyLine);
                    keyUpdated = true;
                    continue;
                }

                newLines.Add(line);
            }

            if (!keyUpdated)
            {
                if (inTable)
                {
                    var insertAt = newLines.FindIndex(static line => IsAnyTableHeader(line.Trim()));
                    if (insertAt >= 0)
                    {
                        newLines.Insert(insertAt, keyLine);
                    }
                    else
                    {
                        newLines.Add(keyLine);
                    }
                }
                else
                {
                    newLines.Add(keyLine);
                }
            }

            return NormalizeOutputContent(newLines);
        }

        var sectionHeader = $"[{keyParts[0]}]";
        var inTargetSection = false;
        var foundSection = false;
        var keyUpdatedNested = false;

        foreach (var line in lines)
        {
            var trimmed = line.Trim();

            if (IsTargetHeader(trimmed, sectionHeader))
            {
                inTargetSection = true;
                foundSection = true;
                newLines.Add(line);
                continue;
            }

            if (inTargetSection && IsAnyTableHeader(trimmed))
            {
                if (!keyUpdatedNested)
                {
                    newLines.Add(keyLine);
                    keyUpdatedNested = true;
                }

                inTargetSection = false;
            }

            if (inTargetSection && Regex.IsMatch(trimmed, $"^{Regex.Escape(keyParts[^1])}\\s*=", RegexOptions.CultureInvariant))
            {
                newLines.Add(keyLine);
                keyUpdatedNested = true;
                continue;
            }

            newLines.Add(line);
        }

        if (inTargetSection && !keyUpdatedNested)
        {
            newLines.Add(keyLine);
            keyUpdatedNested = true;
        }

        if (!foundSection)
        {
            if (newLines.Count > 0 && newLines.Any(static line => !string.IsNullOrWhiteSpace(line)))
            {
                newLines.Add(string.Empty);
            }

            newLines.Add(sectionHeader);
            newLines.Add(keyLine);
        }

        return NormalizeOutputContent(newLines);
    }

    private static string RemoveGlobalKey(string content, string[] keyParts)
    {
        var lines = SplitLines(content);
        var newLines = new List<string>(lines.Count);

        if (keyParts.Length == 1)
        {
            foreach (var line in lines)
            {
                var trimmed = line.Trim();
                if (!IsAnyTableHeader(trimmed) && Regex.IsMatch(trimmed, $"^{Regex.Escape(keyParts[0])}\\s*=", RegexOptions.CultureInvariant))
                {
                    continue;
                }

                newLines.Add(line);
            }

            return NormalizeOutputContent(newLines);
        }

        var sectionHeader = $"[{keyParts[0]}]";
        var inTargetSection = false;
        var sectionStart = -1;

        foreach (var line in lines)
        {
            var trimmed = line.Trim();

            if (IsTargetHeader(trimmed, sectionHeader))
            {
                inTargetSection = true;
                sectionStart = newLines.Count;
                newLines.Add(line);
                continue;
            }

            if (inTargetSection && IsAnyTableHeader(trimmed))
            {
                inTargetSection = false;
            }

            if (inTargetSection && Regex.IsMatch(trimmed, $"^{Regex.Escape(keyParts[^1])}\\s*=", RegexOptions.CultureInvariant))
            {
                continue;
            }

            newLines.Add(line);
        }

        if (sectionStart >= 0)
        {
            var sectionEnd = newLines.Count;
            for (var index = sectionStart + 1; index < newLines.Count; index++)
            {
                if (IsAnyTableHeader(newLines[index].Trim()))
                {
                    sectionEnd = index;
                    break;
                }
            }

            if (!SectionHasContent(newLines, sectionStart + 1, sectionEnd))
            {
                newLines.RemoveRange(sectionStart, sectionEnd - sectionStart);
            }
        }

        return NormalizeOutputContent(newLines);
    }

    private static string? FormatTomlValueForKey(string key, string value)
    {
        var keyName = key.Contains('.', StringComparison.Ordinal)
            ? key[(key.LastIndexOf('.') + 1)..]
            : key;

        var portKeys = new HashSet<string>(StringComparer.Ordinal)
        {
            "port_range_start",
            "port_range_end",
            "ssh.port_range_start",
            "ssh.port_range_end",
        };

        var boolKeys = new HashSet<string>(StringComparer.Ordinal)
        {
            "forward_agent",
            "auto_prompt",
            "exclude_priv",
            "ssh.forward_agent",
            "import.auto_prompt",
            "import.exclude_priv",
        };

        if (portKeys.Contains(key) || portKeys.Contains(keyName))
        {
            if (!int.TryParse(value, NumberStyles.Integer, CultureInfo.InvariantCulture, out var port))
            {
                return null;
            }

            if (port is < 1024 or > 65535)
            {
                return null;
            }

            return port.ToString(CultureInfo.InvariantCulture);
        }

        if (boolKeys.Contains(key) || boolKeys.Contains(keyName))
        {
            return value.ToLowerInvariant() switch
            {
                "true" or "1" or "yes" => "true",
                "false" or "0" or "no" => "false",
                _ => null,
            };
        }

        return FormatTomlString(value);
    }

    private static string FormatTomlString(string value)
    {
        if (value.IndexOfAny(['\n', '\r', '\t', '"', '\\']) >= 0)
        {
            var escaped = value
                .Replace("\\", "\\\\", StringComparison.Ordinal)
                .Replace("\"", "\\\"", StringComparison.Ordinal)
                .Replace("\n", "\\n", StringComparison.Ordinal)
                .Replace("\r", "\\r", StringComparison.Ordinal)
                .Replace("\t", "\\t", StringComparison.Ordinal);
            return $"\"{escaped}\"";
        }

        return $"\"{value}\"";
    }

    private static string EscapeTomlKey(string value)
    {
        return value
            .Replace("\\", "\\\\", StringComparison.Ordinal)
            .Replace("\"", "\\\"", StringComparison.Ordinal);
    }

    private static bool IsAnyTableHeader(string trimmed)
    {
        return trimmed.StartsWith("[", StringComparison.Ordinal);
    }

    private static bool IsTargetHeader(string trimmed, string header)
    {
        if (string.Equals(trimmed, header, StringComparison.Ordinal))
        {
            return true;
        }

        if (trimmed.StartsWith(header, StringComparison.Ordinal) && trimmed.Length > header.Length)
        {
            var remainder = trimmed[header.Length..].TrimStart();
            return remainder.StartsWith("#", StringComparison.Ordinal);
        }

        return false;
    }

    private static bool SectionHasContent(IReadOnlyList<string> lines, int start, int end)
    {
        for (var index = start; index < end && index < lines.Count; index++)
        {
            var trimmed = lines[index].Trim();
            if (trimmed.Length > 0 && !trimmed.StartsWith("#", StringComparison.Ordinal))
            {
                return true;
            }
        }

        return false;
    }

    private static List<string> SplitLines(string content)
    {
        if (string.IsNullOrEmpty(content))
        {
            return [];
        }

        var normalized = content.Replace("\r\n", "\n", StringComparison.Ordinal);
        if (normalized.EndsWith("\n", StringComparison.Ordinal))
        {
            normalized = normalized[..^1];
        }

        return normalized.Length == 0
            ? []
            : normalized.Split('\n').ToList();
    }

    private static string NormalizeOutputContent(IReadOnlyList<string> lines)
    {
        if (lines.Count == 0)
        {
            return string.Empty;
        }

        var content = string.Join("\n", lines);
        return content.Length == 0 || content.EndsWith('\n')
            ? content
            : content + "\n";
    }

    private static (bool Success, object? Value, string? Warning, string? Error) ValidateEnvSection(TomlTable table)
    {
        if (!table.TryGetValue("env", out var envObj) || envObj is null)
        {
            return (true, null, null, null);
        }

        if (envObj is not TomlTable envTable)
        {
            return (false, null, null, "Error: [env] section must be a table/dict");
        }

        var result = new Dictionary<string, object?>(StringComparer.Ordinal);
        string? warning = null;

        if (envTable.TryGetValue("env_file", out var envFileObj) && envFileObj is not null)
        {
            if (envFileObj is not string envFile)
            {
                return (false, null, null, $"Error: [env].env_file must be a string, got {envFileObj.GetType().Name}");
            }

            result["env_file"] = envFile;
        }

        if (envTable.TryGetValue("from_host", out var fromHostObj) && fromHostObj is not null)
        {
            if (fromHostObj is not bool fromHost)
            {
                return (false, null, null, $"Error: [env].from_host must be a boolean, got {fromHostObj.GetType().Name}");
            }

            result["from_host"] = fromHost;
        }
        else
        {
            result["from_host"] = false;
        }

        if (!envTable.TryGetValue("import", out var importsObj) || importsObj is null)
        {
            warning = "[WARN] [env].import missing, treating as empty list";
            result["import"] = Array.Empty<string>();
            return (true, result, warning, null);
        }

        if (importsObj is not TomlArray importsArray)
        {
            warning = $"[WARN] [env].import must be a list, got {importsObj.GetType().Name}; treating as empty list";
            result["import"] = Array.Empty<string>();
            return (true, result, warning, null);
        }

        var validated = new List<string>(importsArray.Count);
        var warnings = new List<string>();
        for (var index = 0; index < importsArray.Count; index++)
        {
            if (importsArray[index] is not string key)
            {
                warnings.Add($"[WARN] [env].import[{index}] must be a string, got {importsArray[index]?.GetType().Name ?? "null"}; skipping");
                continue;
            }

            validated.Add(key);
        }

        result["import"] = validated;
        if (warnings.Count > 0)
        {
            warning = string.Join('\n', warnings);
        }

        return (true, result, warning, null);
    }

    private static (bool Success, object? Value, string? Error) ValidateAgentSection(TomlTable table, string sourceFile)
    {
        if (!table.TryGetValue("agent", out var agentObj) || agentObj is null)
        {
            return (true, null, null);
        }

        if (agentObj is not TomlTable agentTable)
        {
            return (false, null, $"Error: [agent] section must be a table/dict in {sourceFile}");
        }

        if (!agentTable.TryGetValue("name", out var nameObj) || nameObj is not string name || string.IsNullOrEmpty(name))
        {
            return (false, null, $"Error: [agent].name is required in {sourceFile}");
        }

        if (!agentTable.TryGetValue("binary", out var binaryObj) || binaryObj is not string binary || string.IsNullOrEmpty(binary))
        {
            return (false, null, $"Error: [agent].binary is required in {sourceFile}");
        }

        var defaultArgs = new List<string>();
        if (agentTable.TryGetValue("default_args", out var defaultArgsObj) && defaultArgsObj is not null)
        {
            if (defaultArgsObj is not TomlArray defaultArgsArray)
            {
                return (false, null, $"Error: [agent].default_args must be a list, got {defaultArgsObj.GetType().Name} in {sourceFile}");
            }

            for (var index = 0; index < defaultArgsArray.Count; index++)
            {
                if (defaultArgsArray[index] is not string arg)
                {
                    return (false, null, $"Error: [agent].default_args[{index}] must be a string, got {defaultArgsArray[index]?.GetType().Name ?? "null"} in {sourceFile}");
                }

                defaultArgs.Add(arg);
            }
        }

        var aliases = new List<string>();
        if (agentTable.TryGetValue("aliases", out var aliasesObj) && aliasesObj is not null)
        {
            if (aliasesObj is not TomlArray aliasesArray)
            {
                return (false, null, $"Error: [agent].aliases must be a list, got {aliasesObj.GetType().Name} in {sourceFile}");
            }

            for (var index = 0; index < aliasesArray.Count; index++)
            {
                if (aliasesArray[index] is not string alias || string.IsNullOrEmpty(alias))
                {
                    return (false, null, $"Error: [agent].aliases[{index}] must be a non-empty string in {sourceFile}");
                }

                aliases.Add(alias);
            }
        }

        var optional = false;
        if (agentTable.TryGetValue("optional", out var optionalObj) && optionalObj is not null)
        {
            if (optionalObj is not bool optionalBool)
            {
                return (false, null, $"Error: [agent].optional must be a boolean, got {optionalObj.GetType().Name} in {sourceFile}");
            }

            optional = optionalBool;
        }

        var result = new Dictionary<string, object?>(StringComparer.Ordinal)
        {
            ["source_file"] = sourceFile,
            ["name"] = name,
            ["binary"] = binary,
            ["default_args"] = defaultArgs,
            ["aliases"] = aliases,
            ["optional"] = optional,
        };

        return (true, result, null);
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
        catch
        {
            // Best effort only.
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
        catch
        {
            // Best effort only.
        }
    }

    private static bool TryParseArguments(
        IReadOnlyList<string> args,
        out TomlCommandArguments parsed,
        out string error)
    {
        parsed = new TomlCommandArguments();
        error = string.Empty;

        for (var index = 0; index < args.Count; index++)
        {
            var token = args[index];
            switch (token)
            {
                case "--file":
                case "-f":
                    if (!TryReadValue(args, ref index, out var fileValue))
                    {
                        error = "Error: --file requires a value";
                        return false;
                    }

                    parsed.FilePath = fileValue;
                    break;
                case "--key":
                case "-k":
                    if (!TryReadValue(args, ref index, out var keyValue))
                    {
                        error = "Error: --key requires a value";
                        return false;
                    }

                    parsed.Mode = AssignMode(parsed.Mode, TomlMode.Key, ref error);
                    if (!string.IsNullOrEmpty(error))
                    {
                        return false;
                    }

                    parsed.KeyOrExistsArg = keyValue;
                    break;
                case "--json":
                case "-j":
                    parsed.Mode = AssignMode(parsed.Mode, TomlMode.Json, ref error);
                    if (!string.IsNullOrEmpty(error))
                    {
                        return false;
                    }

                    break;
                case "--exists":
                case "-e":
                    if (!TryReadValue(args, ref index, out var existsValue))
                    {
                        error = "Error: --exists requires a value";
                        return false;
                    }

                    parsed.Mode = AssignMode(parsed.Mode, TomlMode.Exists, ref error);
                    if (!string.IsNullOrEmpty(error))
                    {
                        return false;
                    }

                    parsed.KeyOrExistsArg = existsValue;
                    break;
                case "--env":
                    parsed.Mode = AssignMode(parsed.Mode, TomlMode.Env, ref error);
                    if (!string.IsNullOrEmpty(error))
                    {
                        return false;
                    }

                    break;
                case "--get-workspace":
                    if (!TryReadValue(args, ref index, out var wsPath))
                    {
                        error = "Error: --get-workspace requires a value";
                        return false;
                    }

                    parsed.Mode = AssignMode(parsed.Mode, TomlMode.GetWorkspace, ref error);
                    if (!string.IsNullOrEmpty(error))
                    {
                        return false;
                    }

                    parsed.WorkspacePathOrUnsetPath = wsPath;
                    break;
                case "--set-workspace-key":
                    if (!TryReadValue(args, ref index, out var setWsPath) ||
                        !TryReadValue(args, ref index, out var setWsKey) ||
                        !TryReadValue(args, ref index, out var setWsValue))
                    {
                        error = "Error: --set-workspace-key requires PATH KEY VALUE";
                        return false;
                    }

                    parsed.Mode = AssignMode(parsed.Mode, TomlMode.SetWorkspaceKey, ref error);
                    if (!string.IsNullOrEmpty(error))
                    {
                        return false;
                    }

                    parsed.WorkspacePathOrUnsetPath = setWsPath;
                    parsed.WorkspaceKey = setWsKey;
                    parsed.Value = setWsValue;
                    break;
                case "--unset-workspace-key":
                    if (!TryReadValue(args, ref index, out var unsetWsPath) ||
                        !TryReadValue(args, ref index, out var unsetWsKey))
                    {
                        error = "Error: --unset-workspace-key requires PATH KEY";
                        return false;
                    }

                    parsed.Mode = AssignMode(parsed.Mode, TomlMode.UnsetWorkspaceKey, ref error);
                    if (!string.IsNullOrEmpty(error))
                    {
                        return false;
                    }

                    parsed.WorkspacePathOrUnsetPath = unsetWsPath;
                    parsed.WorkspaceKey = unsetWsKey;
                    break;
                case "--set-key":
                    if (!TryReadValue(args, ref index, out var setKey) ||
                        !TryReadValue(args, ref index, out var setValue))
                    {
                        error = "Error: --set-key requires KEY VALUE";
                        return false;
                    }

                    parsed.Mode = AssignMode(parsed.Mode, TomlMode.SetKey, ref error);
                    if (!string.IsNullOrEmpty(error))
                    {
                        return false;
                    }

                    parsed.KeyOrExistsArg = setKey;
                    parsed.Value = setValue;
                    break;
                case "--unset-key":
                    if (!TryReadValue(args, ref index, out var unsetKey))
                    {
                        error = "Error: --unset-key requires KEY";
                        return false;
                    }

                    parsed.Mode = AssignMode(parsed.Mode, TomlMode.UnsetKey, ref error);
                    if (!string.IsNullOrEmpty(error))
                    {
                        return false;
                    }

                    parsed.KeyOrExistsArg = unsetKey;
                    break;
                case "--emit-agents":
                    parsed.Mode = AssignMode(parsed.Mode, TomlMode.EmitAgents, ref error);
                    if (!string.IsNullOrEmpty(error))
                    {
                        return false;
                    }

                    break;
                default:
                    if (token.StartsWith("--file=", StringComparison.Ordinal))
                    {
                        parsed.FilePath = token["--file=".Length..];
                        break;
                    }

                    error = $"Error: Unknown toml option: {token}";
                    return false;
            }
        }

        if (string.IsNullOrWhiteSpace(parsed.FilePath))
        {
            error = "Error: --file is required";
            return false;
        }

        if (parsed.Mode == TomlMode.None)
        {
            error = "Error: Must specify one of --key, --json, --exists, --env, --get-workspace, --set-workspace-key, --unset-workspace-key, --set-key, --unset-key, or --emit-agents";
            return false;
        }

        return true;
    }

    private static TomlMode AssignMode(TomlMode current, TomlMode requested, ref string error)
    {
        if (current == TomlMode.None)
        {
            return requested;
        }

        if (current != requested)
        {
            error = "Error: Options are mutually exclusive";
        }

        return current;
    }

    private static bool TryReadValue(IReadOnlyList<string> args, ref int index, out string value)
    {
        if (index + 1 >= args.Count)
        {
            value = string.Empty;
            return false;
        }

        value = args[++index];
        return true;
    }

    [GeneratedRegex("^[a-zA-Z_][a-zA-Z0-9_]*$", RegexOptions.CultureInvariant)]
    private static partial Regex WorkspaceKeyRegexFactory();

    [GeneratedRegex("^[a-zA-Z_][a-zA-Z0-9_.]*$", RegexOptions.CultureInvariant)]
    private static partial Regex GlobalKeyRegexFactory();

    private enum TomlMode
    {
        None,
        Key,
        Json,
        Exists,
        Env,
        SetWorkspaceKey,
        GetWorkspace,
        UnsetWorkspaceKey,
        SetKey,
        UnsetKey,
        EmitAgents,
    }

    private sealed record TomlCommandArguments
    {
        public string? FilePath { get; set; }

        public TomlMode Mode { get; set; }

        public string? KeyOrExistsArg { get; set; }

        public string? WorkspacePathOrUnsetPath { get; set; }

        public string? WorkspaceKey { get; set; }

        public string? Value { get; set; }
    }
}
