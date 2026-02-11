using System.Text.RegularExpressions;
using ContainAI.Cli.Abstractions;
using ContainAI.Cli.Host.RuntimeSupport;

namespace ContainAI.Cli.Host;

internal abstract partial class CaiRuntimeSupport
{
    protected static string EscapeJson(string value)
        => CaiRuntimeProcessHelpers.EscapeJson(value);

    protected static Task CopyDirectoryAsync(string sourceDirectory, string destinationDirectory, CancellationToken cancellationToken)
        => CaiRuntimeProcessHelpers.CopyDirectoryAsync(sourceDirectory, destinationDirectory, cancellationToken);

    protected static async Task<ProcessResult> RunProcessCaptureAsync(
        string fileName,
        IReadOnlyList<string> arguments,
        CancellationToken cancellationToken,
        string? standardInput = null)
    {
        var result = await CaiRuntimeProcessHelpers
            .RunProcessCaptureAsync(fileName, arguments, cancellationToken, standardInput)
            .ConfigureAwait(false);

        return ToProcessResult(result);
    }

    protected static Task<int> RunProcessInteractiveAsync(
        string fileName,
        IReadOnlyList<string> arguments,
        CancellationToken cancellationToken)
        => CaiRuntimeProcessHelpers.RunProcessInteractiveAsync(fileName, arguments, cancellationToken);

    protected static Task<bool> CommandSucceedsAsync(string fileName, IReadOnlyList<string> arguments, CancellationToken cancellationToken)
        => CaiRuntimeProcessHelpers.CommandSucceedsAsync(fileName, arguments, cancellationToken);

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
}
