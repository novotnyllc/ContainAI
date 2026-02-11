using ContainAI.Cli.Host.RuntimeSupport.Models;
using ContainAI.Cli.Host.RuntimeSupport.Paths;

namespace ContainAI.Cli.Host.RuntimeSupport.Environment;

internal static class CaiRuntimeEnvFileHelpers
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

    internal static RuntimeEnvFilePathResolution ResolveEnvFilePath(string workspaceRoot, string envFile)
    {
        if (Path.IsPathRooted(envFile))
        {
            return new RuntimeEnvFilePathResolution(null, $"env_file path rejected: absolute paths are not allowed (must be workspace-relative): {envFile}");
        }

        var candidate = Path.GetFullPath(Path.Combine(workspaceRoot, envFile));
        var workspacePrefix = workspaceRoot.EndsWith(Path.DirectorySeparatorChar.ToString(), StringComparison.Ordinal)
            ? workspaceRoot
            : workspaceRoot + Path.DirectorySeparatorChar;
        if (!candidate.StartsWith(workspacePrefix, StringComparison.Ordinal) && !string.Equals(candidate, workspaceRoot, StringComparison.Ordinal))
        {
            return new RuntimeEnvFilePathResolution(null, $"env_file path rejected: outside workspace boundary: {envFile}");
        }

        if (!File.Exists(candidate))
        {
            return new RuntimeEnvFilePathResolution(null, null);
        }

        if (CaiRuntimePathHelpers.IsSymbolicLinkPath(candidate))
        {
            return new RuntimeEnvFilePathResolution(null, $"env_file is a symlink (rejected): {candidate}");
        }

        return new RuntimeEnvFilePathResolution(candidate, null);
    }
}
