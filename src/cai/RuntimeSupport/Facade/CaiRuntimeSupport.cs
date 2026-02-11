using System.Text.RegularExpressions;
using ContainAI.Cli.Abstractions;
using ContainAI.Cli.Host.RuntimeSupport.Docker;
using ContainAI.Cli.Host.RuntimeSupport.Environment;
using ContainAI.Cli.Host.RuntimeSupport.Models;
using ContainAI.Cli.Host.RuntimeSupport.Parsing;
using ContainAI.Cli.Host.RuntimeSupport.Paths;
using ContainAI.Cli.Host.RuntimeSupport.Process;

namespace ContainAI.Cli.Host;

internal abstract class CaiRuntimeSupport
{
    protected readonly TextWriter stdout;
    protected readonly TextWriter stderr;

    protected static readonly string[] ConfigFileNames =
    [
        "config.toml",
        "containai.toml",
    ];

    protected CaiRuntimeSupport(TextWriter standardOutput, TextWriter standardError)
    {
        stdout = standardOutput;
        stderr = standardError;
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

    protected static bool IsExecutableOnPath(string fileName)
        => CaiRuntimePathResolutionHelpers.IsExecutableOnPath(fileName);

    protected static Task<string> ResolveChannelAsync(CancellationToken cancellationToken)
        => CaiRuntimePathResolutionHelpers.ResolveChannelAsync(ConfigFileNames, cancellationToken);

    protected static Task<string?> ResolveDataVolumeAsync(string workspace, string? explicitVolume, CancellationToken cancellationToken)
        => CaiRuntimePathResolutionHelpers.ResolveDataVolumeAsync(workspace, explicitVolume, ConfigFileNames, cancellationToken);

    protected static string ResolveUserConfigPath()
        => CaiRuntimeConfigPathHelpers.ResolveUserConfigPath(ConfigFileNames);

    protected static string? TryFindExistingUserConfigPath()
        => CaiRuntimeConfigPathHelpers.TryFindExistingUserConfigPath(ConfigFileNames);

    protected static string ResolveConfigPath(string? workspacePath)
        => CaiRuntimeConfigPathHelpers.ResolveConfigPath(workspacePath, ConfigFileNames);

    protected static string ResolveTemplatesDirectory()
        => CaiRuntimeConfigPathHelpers.ResolveTemplatesDirectory();

    protected static string ResolveHomeDirectory()
        => CaiRuntimeHomePathHelpers.ResolveHomeDirectory();

    protected static string ExpandHomePath(string path)
        => CaiRuntimeHomePathHelpers.ExpandHomePath(path);

    protected static string? TryFindWorkspaceConfigPath(string? workspacePath)
        => CaiRuntimeWorkspacePathHelpers.TryFindWorkspaceConfigPath(workspacePath, ConfigFileNames);

    protected static bool IsSymbolicLinkPath(string path)
        => CaiRuntimePathHelpers.IsSymbolicLinkPath(path);

    protected static bool TryMapSourcePathToTarget(
        string sourceRelativePath,
        IReadOnlyList<ManifestEntry> entries,
        out string targetRelativePath,
        out string flags)
        => CaiRuntimePathHelpers.TryMapSourcePathToTarget(sourceRelativePath, entries, out targetRelativePath, out flags);

    protected static string EscapeForSingleQuotedShell(string value)
        => CaiRuntimePathHelpers.EscapeForSingleQuotedShell(value);

    protected static Task<bool> DockerContainerExistsAsync(string containerName, CancellationToken cancellationToken)
        => CaiRuntimeDockerHelpers.DockerContainerExistsAsync(containerName, cancellationToken);

    protected static Task<int> DockerRunAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => CaiRuntimeDockerHelpers.DockerRunAsync(args, cancellationToken);

    protected static async Task<ProcessResult> DockerCaptureAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        var result = await CaiRuntimeDockerHelpers.DockerCaptureAsync(args, cancellationToken).ConfigureAwait(false);
        return ToProcessResult(result);
    }

    protected static async Task<ProcessResult> DockerCaptureAsync(IReadOnlyList<string> args, string standardInput, CancellationToken cancellationToken)
    {
        var result = await CaiRuntimeDockerHelpers.DockerCaptureAsync(args, standardInput, cancellationToken).ConfigureAwait(false);
        return ToProcessResult(result);
    }

    protected static Task<CommandExecutionResult> ExecuteDockerCommandAsync(
        IReadOnlyList<string> args,
        string? standardInput,
        CancellationToken cancellationToken)
        => CaiRuntimeDockerHelpers.ExecuteDockerCommandAsync(args, standardInput, cancellationToken);

    protected static Task<string?> ResolveDockerContextAsync(CancellationToken cancellationToken)
        => CaiRuntimeDockerHelpers.ResolveDockerContextAsync(cancellationToken);

    protected static Task<List<string>> FindContainerContextsAsync(string containerName, CancellationToken cancellationToken)
        => CaiRuntimeDockerHelpers.FindContainerContextsAsync(containerName, cancellationToken);

    protected static Task<List<string>> GetAvailableContextsAsync(CancellationToken cancellationToken)
        => CaiRuntimeDockerHelpers.GetAvailableContextsAsync(cancellationToken);

    protected static async Task<ProcessResult> DockerCaptureForContextAsync(string context, IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        var result = await CaiRuntimeDockerHelpers.DockerCaptureForContextAsync(context, args, cancellationToken).ConfigureAwait(false);
        return ToProcessResult(result);
    }

    protected static Task<string?> ResolveDataVolumeFromContainerAsync(string containerName, string? explicitVolume, CancellationToken cancellationToken)
        => CaiRuntimeDockerHelpers.ResolveDataVolumeFromContainerAsync(containerName, explicitVolume, cancellationToken);

    protected static string EscapeJson(string value)
        => CaiRuntimeJsonEscaper.EscapeJson(value);

    protected static Task CopyDirectoryAsync(string sourceDirectory, string destinationDirectory, CancellationToken cancellationToken)
        => CaiRuntimeDirectoryCopier.CopyDirectoryAsync(sourceDirectory, destinationDirectory, cancellationToken);

    protected static async Task<ProcessResult> RunProcessCaptureAsync(
        string fileName,
        IReadOnlyList<string> arguments,
        CancellationToken cancellationToken,
        string? standardInput = null)
    {
        var result = await CaiRuntimeProcessRunner
            .RunProcessCaptureAsync(fileName, arguments, cancellationToken, standardInput)
            .ConfigureAwait(false);

        return ToProcessResult(result);
    }

    protected static Task<int> RunProcessInteractiveAsync(
        string fileName,
        IReadOnlyList<string> arguments,
        CancellationToken cancellationToken)
        => CaiRuntimeProcessRunner.RunProcessInteractiveAsync(fileName, arguments, cancellationToken);

    protected static Task<bool> CommandSucceedsAsync(string fileName, IReadOnlyList<string> arguments, CancellationToken cancellationToken)
        => CaiRuntimeProcessRunner.CommandSucceedsAsync(fileName, arguments, cancellationToken);

    protected Task<string?> ResolveWorkspaceContainerNameAsync(string workspace, CancellationToken cancellationToken)
        => CaiRuntimeCommandParsingHelpers.ResolveWorkspaceContainerNameAsync(workspace, stderr, ConfigFileNames, cancellationToken);

    protected static EnvFilePathResolution ResolveEnvFilePath(string workspaceRoot, string envFile)
    {
        var result = CaiRuntimeEnvFileHelpers.ResolveEnvFilePath(workspaceRoot, envFile);
        return new EnvFilePathResolution(result.Path, result.Error);
    }

    protected static ParsedEnvFile ParseEnvFile(string filePath)
    {
        var parsed = CaiRuntimeEnvFileHelpers.ParseEnvFile(filePath);
        return new ParsedEnvFile(parsed.Values, parsed.Warnings);
    }

    protected static Regex EnvVarNameRegex() => CaiRuntimeEnvRegexHelpers.EnvVarNameRegex();

    protected static async Task<ProcessResult> RunTomlAsync(Func<TomlCommandResult> operation, CancellationToken cancellationToken)
    {
        var result = await CaiRuntimeParseAndTimeHelpers.RunTomlAsync(operation, cancellationToken).ConfigureAwait(false);
        return ToProcessResult(result);
    }

    protected static string NormalizeConfigKey(string key)
        => CaiRuntimeParseAndTimeHelpers.NormalizeConfigKey(key);

    protected static (string? Workspace, string? Error) ResolveWorkspaceScope(ParsedConfigCommand parsed, string normalizedKey)
        => CaiRuntimeParseAndTimeHelpers.ResolveWorkspaceScope(parsed.Global, parsed.Workspace, normalizedKey);

    protected static bool TryParseAgeDuration(string value, out TimeSpan duration)
        => CaiRuntimeParseAndTimeHelpers.TryParseAgeDuration(value, out duration);

    protected static DateTimeOffset? ParseGcReferenceTime(string finishedAtRaw, string createdRaw)
        => CaiRuntimeParseAndTimeHelpers.ParseGcReferenceTime(finishedAtRaw, createdRaw);

    private static ProcessResult ToProcessResult(RuntimeProcessResult result)
        => new(result.ExitCode, result.StandardOutput, result.StandardError);
}
