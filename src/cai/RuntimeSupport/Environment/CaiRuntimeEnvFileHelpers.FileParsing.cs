namespace ContainAI.Cli.Host.RuntimeSupport;

internal static partial class CaiRuntimeEnvFileHelpers
{
    internal static RuntimeParsedEnvFile ParseEnvFile(string filePath)
    {
        var values = new Dictionary<string, string>(StringComparer.Ordinal);
        var warnings = new List<string>();
        using var reader = new StreamReader(filePath);
        var lineNumber = 0;
        while (reader.ReadLine() is { } line)
        {
            lineNumber++;
            var normalized = line.TrimEnd('\r');
            if (string.IsNullOrWhiteSpace(normalized) || normalized.StartsWith('#'))
            {
                continue;
            }

            if (normalized.StartsWith("export ", StringComparison.Ordinal))
            {
                normalized = normalized[7..].TrimStart();
            }

            var separatorIndex = normalized.IndexOf('=', StringComparison.Ordinal);
            if (separatorIndex <= 0)
            {
                warnings.Add($"[WARN] line {lineNumber}: no = found - skipping");
                continue;
            }

            var key = normalized[..separatorIndex];
            var value = normalized[(separatorIndex + 1)..];
            if (!CaiRuntimeEnvRegexHelpers.EnvVarNameRegex().IsMatch(key))
            {
                warnings.Add($"[WARN] line {lineNumber}: key '{key}' invalid format - skipping");
                continue;
            }

            if (value.StartsWith('"') && !value[1..].Contains('"', StringComparison.Ordinal))
            {
                warnings.Add($"[WARN] line {lineNumber}: key '{key}' skipped (multiline value)");
                continue;
            }

            if (value.StartsWith('\'') && !value[1..].Contains('\'', StringComparison.Ordinal))
            {
                warnings.Add($"[WARN] line {lineNumber}: key '{key}' skipped (multiline value)");
                continue;
            }

            values[key] = value;
        }

        return new RuntimeParsedEnvFile(values, warnings);
    }
}
