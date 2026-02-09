using System.ComponentModel;
using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal abstract partial class CaiRuntimeSupport
{

    protected static string EscapeJson(string value)
    {
        if (string.IsNullOrEmpty(value))
        {
            return string.Empty;
        }

        return value
            .Replace("\\", "\\\\", StringComparison.Ordinal)
            .Replace("\"", "\\\"", StringComparison.Ordinal)
            .Replace("\r", "\\r", StringComparison.Ordinal)
            .Replace("\n", "\\n", StringComparison.Ordinal)
            .Replace("\t", "\\t", StringComparison.Ordinal);
    }

    protected static bool IsSymbolicLinkPath(string path)
    {
        try
        {
            return (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0;
        }
        catch (IOException)
        {
            return false;
        }
        catch (UnauthorizedAccessException)
        {
            return false;
        }
        catch (NotSupportedException)
        {
            return false;
        }
        catch (ArgumentException)
        {
            return false;
        }
    }

    protected static bool TryMapSourcePathToTarget(
        string sourceRelativePath,
        IReadOnlyList<ManifestEntry> entries,
        out string targetRelativePath,
        out string flags)
    {
        targetRelativePath = string.Empty;
        flags = string.Empty;

        var normalizedSource = sourceRelativePath.Replace("\\", "/", StringComparison.Ordinal);
        ManifestEntry? match = null;
        var bestLength = -1;
        string? suffix = null;

        foreach (var entry in entries)
        {
            if (string.IsNullOrWhiteSpace(entry.Source))
            {
                continue;
            }

            var entrySource = entry.Source.Replace("\\", "/", StringComparison.Ordinal).TrimEnd('/');
            var isDirectory = entry.Flags.Contains('d', StringComparison.Ordinal);
            if (isDirectory)
            {
                var prefix = $"{entrySource}/";
                if (!normalizedSource.StartsWith(prefix, StringComparison.Ordinal) &&
                    !string.Equals(normalizedSource, entrySource, StringComparison.Ordinal))
                {
                    continue;
                }

                if (entrySource.Length <= bestLength)
                {
                    continue;
                }

                match = entry;
                bestLength = entrySource.Length;
                suffix = string.Equals(normalizedSource, entrySource, StringComparison.Ordinal)
                    ? string.Empty
                    : normalizedSource[prefix.Length..];
                continue;
            }

            if (!string.Equals(normalizedSource, entrySource, StringComparison.Ordinal))
            {
                continue;
            }

            if (entrySource.Length <= bestLength)
            {
                continue;
            }

            match = entry;
            bestLength = entrySource.Length;
            suffix = null;
        }

        if (match is null)
        {
            return false;
        }

        flags = match.Value.Flags;
        targetRelativePath = string.IsNullOrEmpty(suffix)
            ? match.Value.Target
            : $"{match.Value.Target.TrimEnd('/')}/{suffix}";
        return true;
    }

    protected static string EscapeForSingleQuotedShell(string value)
        => value.Replace("'", "'\"'\"'", StringComparison.Ordinal);

    protected static EnvFilePathResolution ResolveEnvFilePath(string workspaceRoot, string envFile)
    {
        if (Path.IsPathRooted(envFile))
        {
            return new EnvFilePathResolution(null, $"env_file path rejected: absolute paths are not allowed (must be workspace-relative): {envFile}");
        }

        var candidate = Path.GetFullPath(Path.Combine(workspaceRoot, envFile));
        var workspacePrefix = workspaceRoot.EndsWith(Path.DirectorySeparatorChar.ToString(), StringComparison.Ordinal)
            ? workspaceRoot
            : workspaceRoot + Path.DirectorySeparatorChar;
        if (!candidate.StartsWith(workspacePrefix, StringComparison.Ordinal) && !string.Equals(candidate, workspaceRoot, StringComparison.Ordinal))
        {
            return new EnvFilePathResolution(null, $"env_file path rejected: outside workspace boundary: {envFile}");
        }

        if (!File.Exists(candidate))
        {
            return new EnvFilePathResolution(null, null);
        }

        if (IsSymbolicLinkPath(candidate))
        {
            return new EnvFilePathResolution(null, $"env_file is a symlink (rejected): {candidate}");
        }

        return new EnvFilePathResolution(candidate, null);
    }

    protected static ParsedEnvFile ParseEnvFile(string filePath)
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
            if (!EnvVarNameRegex().IsMatch(key))
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

        return new ParsedEnvFile(values, warnings);
    }

    [GeneratedRegex("^[A-Za-z_][A-Za-z0-9_]*$", RegexOptions.CultureInvariant)]
    protected static partial Regex EnvVarNameRegex();

    protected static async Task<bool> CommandSucceedsAsync(string fileName, IReadOnlyList<string> arguments, CancellationToken cancellationToken)
    {
        var result = await RunProcessCaptureAsync(fileName, arguments, cancellationToken).ConfigureAwait(false);
        return result.ExitCode == 0;
    }

    protected async Task<string?> ResolveWorkspaceContainerNameAsync(string workspace, CancellationToken cancellationToken)
    {
        var configPath = ResolveConfigPath(workspace);
        if (File.Exists(configPath))
        {
            var workspaceResult = await RunTomlAsync(
                () => TomlCommandProcessor.GetWorkspace(configPath, workspace),
                cancellationToken).ConfigureAwait(false);

            if (workspaceResult.ExitCode == 0 && !string.IsNullOrWhiteSpace(workspaceResult.StandardOutput))
            {
                using var json = JsonDocument.Parse(workspaceResult.StandardOutput);
                if (json.RootElement.ValueKind == JsonValueKind.Object &&
                    json.RootElement.TryGetProperty("container_name", out var containerNameElement))
                {
                    var configuredName = containerNameElement.GetString();
                    if (!string.IsNullOrWhiteSpace(configuredName))
                    {
                        var inspect = await DockerCaptureAsync(
                            ["inspect", "--type", "container", configuredName],
                            cancellationToken).ConfigureAwait(false);
                        if (inspect.ExitCode == 0)
                        {
                            return configuredName;
                        }
                    }
                }
            }
        }

        var byLabel = await DockerCaptureAsync(
            ["ps", "-aq", "--filter", $"label=containai.workspace={workspace}"],
            cancellationToken).ConfigureAwait(false);

        if (byLabel.ExitCode != 0)
        {
            return null;
        }

        var ids = byLabel.StandardOutput
            .Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

        if (ids.Length == 0)
        {
            return null;
        }

        if (ids.Length > 1)
        {
            await stderr.WriteLineAsync($"Multiple containers found for workspace: {workspace}").ConfigureAwait(false);
            return null;
        }

        var nameResult = await DockerCaptureAsync(
            ["inspect", "--format", "{{.Name}}", ids[0]],
            cancellationToken).ConfigureAwait(false);

        if (nameResult.ExitCode != 0)
        {
            return null;
        }

        return nameResult.StandardOutput.Trim().TrimStart('/');
    }

    protected static async Task CopyDirectoryAsync(string sourceDirectory, string destinationDirectory, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        Directory.CreateDirectory(destinationDirectory);

        foreach (var sourceFile in Directory.EnumerateFiles(sourceDirectory))
        {
            cancellationToken.ThrowIfCancellationRequested();
            var destinationFile = Path.Combine(destinationDirectory, Path.GetFileName(sourceFile));
            using var sourceStream = File.OpenRead(sourceFile);
            using var destinationStream = File.Create(destinationFile);
            await sourceStream.CopyToAsync(destinationStream, cancellationToken).ConfigureAwait(false);
        }

        foreach (var sourceSubdirectory in Directory.EnumerateDirectories(sourceDirectory))
        {
            cancellationToken.ThrowIfCancellationRequested();
            var destinationSubdirectory = Path.Combine(destinationDirectory, Path.GetFileName(sourceSubdirectory));
            await CopyDirectoryAsync(sourceSubdirectory, destinationSubdirectory, cancellationToken).ConfigureAwait(false);
        }
    }

    protected static async Task<ProcessResult> RunProcessCaptureAsync(
        string fileName,
        IReadOnlyList<string> arguments,
        CancellationToken cancellationToken,
        string? standardInput = null)
    {
        try
        {
            var result = await CliWrapProcessRunner
                .RunCaptureAsync(fileName, arguments, cancellationToken, standardInput: standardInput)
                .ConfigureAwait(false);

            return new ProcessResult(result.ExitCode, result.StandardOutput, result.StandardError);
        }
        catch (System.ComponentModel.Win32Exception ex) when (!cancellationToken.IsCancellationRequested)
        {
            return new ProcessResult(1, string.Empty, ex.Message);
        }
        catch (InvalidOperationException ex) when (!cancellationToken.IsCancellationRequested)
        {
            return new ProcessResult(1, string.Empty, ex.Message);
        }
        catch (IOException ex) when (!cancellationToken.IsCancellationRequested)
        {
            return new ProcessResult(1, string.Empty, ex.Message);
        }
    }

    protected static async Task<int> RunProcessInteractiveAsync(
        string fileName,
        IReadOnlyList<string> arguments,
        CancellationToken cancellationToken)
    {
        try
        {
            return await CliWrapProcessRunner.RunInteractiveAsync(fileName, arguments, cancellationToken).ConfigureAwait(false);
        }
        catch (System.ComponentModel.Win32Exception ex) when (!cancellationToken.IsCancellationRequested)
        {
            await Console.Error.WriteLineAsync($"Failed to start '{fileName}': {ex.Message}").ConfigureAwait(false);
            return 127;
        }
        catch (InvalidOperationException ex) when (!cancellationToken.IsCancellationRequested)
        {
            await Console.Error.WriteLineAsync($"Failed to start '{fileName}': {ex.Message}").ConfigureAwait(false);
            return 127;
        }
        catch (IOException ex) when (!cancellationToken.IsCancellationRequested)
        {
            await Console.Error.WriteLineAsync($"Failed to start '{fileName}': {ex.Message}").ConfigureAwait(false);
            return 127;
        }
    }

    protected readonly record struct ProcessResult(int ExitCode, string StandardOutput, string StandardError);

    protected readonly record struct ParsedImportOptions(
        string? SourcePath,
        string? ExplicitVolume,
        string? Workspace,
        string? ConfigPath,
        bool DryRun,
        bool NoExcludes,
        bool NoSecrets,
        bool Verbose,
        string? Error);

    protected readonly record struct AdditionalImportPath(
        string SourcePath,
        string TargetPath,
        bool IsDirectory,
        bool ApplyPrivFilter);

    protected readonly record struct ImportedSymlink(
        string RelativePath,
        string Target);

    protected readonly record struct EnvFilePathResolution(string? Path, string? Error);
    protected readonly record struct ParsedEnvFile(
        IReadOnlyDictionary<string, string> Values,
        IReadOnlyList<string> Warnings);

    protected readonly record struct ParsedConfigCommand(
        string Action,
        string? Key,
        string? Value,
        bool Global,
        string? Workspace,
        string? Error);
}
